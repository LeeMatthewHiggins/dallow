import 'dart:io';

import 'package:dallow/src/checks/circular_import_check.dart';
import 'package:dallow/src/checks/complexity_check.dart';
import 'package:dallow/src/checks/duplication_check.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/gate.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Thrown when a `dallow.yaml` file cannot be read or holds a key, value or
/// glob dallow does not understand. A misread configuration is refused rather
/// than partly applied, so a typo can never produce a falsely-clean report.
class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How a rule in the `rules:` section treats the findings of one [CheckKind]:
/// report them at a fixed [severity], or drop them ([off]).
enum RuleLevel {
  error(Severity.error),
  warning(Severity.warning),
  info(Severity.info),
  off(null);

  const RuleLevel(this.severity);

  /// The severity findings are reported at, or null when the rule is off.
  final Severity? severity;
}

/// The settings read from a package's `dallow.yaml`.
///
/// Every field is optional; [DallowConfig.defaults] is what a package without
/// a configuration file gets. A command-line flag always wins over the value
/// configured here.
class DallowConfig {
  const DallowConfig({
    this.exclude = const [],
    this.reportGenerated = false,
    this.generatedPatterns = const [],
    this.failOn,
    this.rules = const {},
    this.ignoredDependencies = const {},
    this.maxCycleSize,
    this.minBlockSize,
    this.duplicationExclude = const [],
    this.duplicationIncludesTests = false,
    this.maxComplexity,
  });

  /// Parses the YAML [content] of a configuration file. [source] names the
  /// file in error messages.
  factory DallowConfig.parse(String content, {String source = fileName}) =>
      _ConfigParser(source).parse(content);

  /// Reads the configuration file at [path], which must exist.
  factory DallowConfig.fromFile(String path) {
    final String content;
    try {
      content = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      throw ConfigException('Could not read config file $path: ${e.message}');
    }
    return DallowConfig.parse(content, source: path);
  }

  /// Reads the configuration of the package at [packageRoot].
  ///
  /// Uses the package's own `dallow.yaml` when it has one, otherwise the one
  /// at [fallbackRoot] (a workspace root shared by its member packages), and
  /// otherwise [defaults].
  factory DallowConfig.forPackage(String packageRoot, {String? fallbackRoot}) {
    for (final root in [packageRoot, if (fallbackRoot != null) fallbackRoot]) {
      final file = File(p.join(root, fileName));
      if (file.existsSync()) return DallowConfig.fromFile(file.path);
    }
    return defaults;
  }

  /// The file dallow looks for at the root of a package.
  static const fileName = 'dallow.yaml';

  /// The configuration of a package that has no `dallow.yaml`.
  static const defaults = DallowConfig();

  /// Globs of files whose findings are never reported. The files still feed
  /// the symbol graph, so code they reference stays reachable.
  final List<String> exclude;

  /// Whether findings located in generated files are reported.
  final bool reportGenerated;

  /// Globs marking files as generated, in addition to the built-in patterns
  /// and the generated-code header.
  final List<String> generatedPatterns;

  /// The lowest severity that fails the run, when the configuration sets one.
  final FailOn? failOn;

  /// Per-kind severity overrides.
  final Map<CheckKind, RuleLevel> rules;

  /// Packages the dependency check never reports.
  final Set<String> ignoredDependencies;

  final int? maxCycleSize;
  final int? minBlockSize;

  /// Globs of files left out of duplicate detection only.
  final List<String> duplicationExclude;

  /// Whether duplicate detection scans test code (`test/`,
  /// `integration_test/`, `test_driver/`). Tests repeat their arrange-and-
  /// assert scaffolding by design, so they are left out unless this is set.
  final bool duplicationIncludesTests;

  final int? maxComplexity;

  /// Returns this configuration with each non-null argument replacing the
  /// configured value — how a command-line flag takes precedence.
  DallowConfig overriddenBy({
    int? maxCycleSize,
    int? minBlockSize,
    int? maxComplexity,
    bool? reportGenerated,
    bool? duplicationIncludesTests,
  }) =>
      DallowConfig(
        exclude: exclude,
        reportGenerated: reportGenerated ?? this.reportGenerated,
        generatedPatterns: generatedPatterns,
        failOn: failOn,
        rules: rules,
        ignoredDependencies: ignoredDependencies,
        maxCycleSize: maxCycleSize ?? this.maxCycleSize,
        minBlockSize: minBlockSize ?? this.minBlockSize,
        duplicationExclude: duplicationExclude,
        duplicationIncludesTests:
            duplicationIncludesTests ?? this.duplicationIncludesTests,
        maxComplexity: maxComplexity ?? this.maxComplexity,
      );
}

abstract final class _Keys {
  static const exclude = 'exclude';
  static const generated = 'generated';
  static const report = 'report';
  static const patterns = 'patterns';
  static const failOn = 'fail-on';
  static const rules = 'rules';
  static const dependencies = 'dependencies';
  static const ignore = 'ignore';
  static const circular = 'circular';
  static const maxCycleSize = 'max-cycle-size';
  static const duplication = 'duplication';
  static const minBlockSize = 'min-block-size';
  static const includeTests = 'include-tests';
  static const complexity = 'complexity';
  static const maxComplexity = 'max-complexity';

  static const Set<String> topLevel = {
    exclude,
    generated,
    failOn,
    rules,
    dependencies,
    circular,
    duplication,
    complexity,
  };
}

class _ConfigParser {
  _ConfigParser(this._source);

  final String _source;

  DallowConfig parse(String content) {
    final Object? document;
    try {
      document = loadYaml(content);
    } on YamlException catch (e) {
      throw _error('is not valid YAML: ${e.message}');
    }
    if (document == null) return DallowConfig.defaults;

    final root = _section(document, 'the document');
    _rejectUnknownKeys(root, _Keys.topLevel, 'top-level');

    final generated = _subsection(root, _Keys.generated, {
      _Keys.report,
      _Keys.patterns,
    });
    final dependencies = _subsection(root, _Keys.dependencies, {_Keys.ignore});
    final circular = _subsection(root, _Keys.circular, {_Keys.maxCycleSize});
    final duplication = _subsection(root, _Keys.duplication, {
      _Keys.minBlockSize,
      _Keys.exclude,
      _Keys.includeTests,
    });
    final complexity = _subsection(root, _Keys.complexity, {
      _Keys.maxComplexity,
    });

    return DallowConfig(
      exclude: _globs(root, _Keys.exclude),
      reportGenerated: _bool(generated, _Keys.report) ?? false,
      generatedPatterns: _globs(generated, _Keys.patterns),
      failOn: _enumValue(root, _Keys.failOn, FailOn.values),
      rules: _rules(root),
      ignoredDependencies: _strings(dependencies, _Keys.ignore).toSet(),
      maxCycleSize: _int(circular, _Keys.maxCycleSize, min: minCycleSize),
      minBlockSize: _int(
        duplication,
        _Keys.minBlockSize,
        min: minDuplicateBlockSize,
      ),
      duplicationExclude: _globs(duplication, _Keys.exclude),
      duplicationIncludesTests: _bool(duplication, _Keys.includeTests) ?? false,
      maxComplexity: _int(
        complexity,
        _Keys.maxComplexity,
        min: minComplexityThreshold,
      ),
    );
  }

  Map<CheckKind, RuleLevel> _rules(YamlMap root) {
    final section = _subsection(root, _Keys.rules, {
      for (final kind in _configurableKinds) kind.id,
    });
    return {
      for (final key in section.keys.cast<String>())
        _configurableKinds.firstWhere((kind) => kind.id == key): _ruleLevel(
          section,
          key,
        ),
    };
  }

  /// `unused-ignore` findings exist only under `--report-unused-ignores`, so
  /// that flag — not a rule — is what controls them.
  static final List<CheckKind> _configurableKinds = CheckKind.values
      .where((kind) => kind != CheckKind.unusedIgnore)
      .toList(growable: false);

  /// YAML reads a bare `off` as a string but `false` as a boolean; both turn
  /// a rule off.
  RuleLevel _ruleLevel(YamlMap section, String key) {
    if (section[key] == false) return RuleLevel.off;
    return _enumValue(section, key, RuleLevel.values)!;
  }

  YamlMap _section(Object? value, String description) {
    if (value is YamlMap) return value;
    throw _error('$description must be a map of keys to values.');
  }

  YamlMap _subsection(YamlMap parent, String key, Set<String> allowed) {
    final value = parent[key];
    if (value == null) return YamlMap();
    final section = _section(value, "'$key'");
    _rejectUnknownKeys(section, allowed, "'$key'");
    return section;
  }

  void _rejectUnknownKeys(YamlMap map, Set<String> allowed, String where) {
    for (final key in map.keys) {
      if (allowed.contains(key)) continue;
      final known = allowed.toList()..sort();
      throw _error(
        "unknown $where key '$key'. Known keys: ${known.join(', ')}.",
      );
    }
  }

  List<String> _strings(YamlMap map, String key) {
    final value = map[key];
    if (value == null) return const [];
    if (value is YamlList && value.every((item) => item is String)) {
      return value.cast<String>().toList(growable: false);
    }
    throw _error("'$key' must be a list of strings.");
  }

  List<String> _globs(YamlMap map, String key) {
    final patterns = _strings(map, key);
    for (final pattern in patterns) {
      try {
        Glob(pattern, context: p.posix);
      } on FormatException catch (e) {
        throw _error("'$key' holds an invalid glob '$pattern': ${e.message}");
      }
    }
    return patterns;
  }

  bool? _bool(YamlMap map, String key) {
    final value = map[key];
    if (value == null || value is bool) return value as bool?;
    throw _error("'$key' must be true or false.");
  }

  int? _int(YamlMap map, String key, {required int min}) {
    final value = map[key];
    if (value == null) return null;
    if (value is! int) throw _error("'$key' must be an integer.");
    if (value < min) throw _error("'$key' must be at least $min.");
    return value;
  }

  T? _enumValue<T extends Enum>(YamlMap map, String key, List<T> values) {
    final value = map[key];
    if (value == null) return null;
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    final allowed = values.map((v) => v.name).join(', ');
    throw _error("'$key' must be one of: $allowed.");
  }

  ConfigException _error(String problem) =>
      ConfigException('Invalid config $_source: $problem');
}
