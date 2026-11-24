import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'dallow',
    'Codebase intelligence for Dart and Flutter.',
  )
    ..addCommand(_AnalyzeCommand())
    ..addCommand(_DeadCodeCommand())
    ..addCommand(_DepsCommand())
    ..addCommand(_CircularCommand())
    ..addCommand(_DuplicationCommand())
    ..addCommand(_ComplexityCommand());
  runner.argParser.addFlag(
    'version',
    negatable: false,
    help: 'Print the dallow version and the analyzer version it runs on.',
  );

  try {
    final topLevel = runner.parse(args);
    if (topLevel['version'] as bool) {
      stdout.writeln(
          'dallow $dallowVersion (analyzer ${await analyzerVersion()})');
      exit(0);
    }
    final code = await runner.runCommand(topLevel) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(_ExitCode.usage);
  }
}

abstract final class _ExitCode {
  static const success = 0;
  static const usage = 64;
  static const sdkNotFound = 69;
  static const unresolvedSource = 78;
}

/// A problem with how the command was invoked.
class _UsageError implements Exception {
  _UsageError(this.message);

  final String message;
}

/// The settings given as command-line flags. A null field means the flag was
/// absent and the configured value applies.
class _Overrides {
  const _Overrides({
    required this.maxCycleSize,
    required this.minBlockSize,
    required this.maxComplexity,
    required this.reportGenerated,
    required this.duplicationIncludesTests,
  });

  final int? maxCycleSize;
  final int? minBlockSize;
  final int? maxComplexity;
  final bool? reportGenerated;
  final bool? duplicationIncludesTests;
}

abstract class _CheckCommand extends Command<int> {
  _CheckCommand() {
    argParser
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['console', 'json', 'markdown', 'sarif'],
        defaultsTo: 'console',
        help: 'Output format. `sarif` emits a SARIF 2.1.0 log for '
            'code-scanning platforms.',
      )
      ..addOption(
        'fail-on',
        allowed: ['error', 'warning', 'info', 'never'],
        help: 'Lowest severity that causes a non-zero exit code. Defaults to '
            'the fail-on value in ${DallowConfig.fileName}, else error.',
      )
      ..addOption(
        'config',
        abbr: 'c',
        help: 'Read settings from this file instead of the '
            '${DallowConfig.fileName} at the package root. In a recursive '
            'run it applies to every package.',
      )
      ..addFlag(
        'include-generated',
        negatable: false,
        help: 'Report findings located in generated code (*.g.dart, '
            '*.freezed.dart, files with a generated-code header, ...). They '
            'are left out by default.',
      )
      ..addOption(
        'max-cycle-size',
        help: 'Skip dependency cycles with more than this many files. Useful '
            'to ignore a known barrel mega-cycle while still catching small '
            'new cycles.',
      )
      ..addOption(
        'changed-since',
        help: 'Only report findings in files changed since this git ref '
            '(merge-base of <ref>...HEAD), e.g. origin/main or a SHA. '
            'Whole-package findings (no file / pubspec-level) are always '
            'kept. Requires the package to be inside a git work tree.',
      )
      ..addOption(
        'baseline',
        help: 'Suppress findings recorded in this JSON baseline file, so the '
            'gate fails only on findings introduced after it was written.',
      )
      ..addOption(
        'write-baseline',
        help: 'Write the current findings to this file as a baseline and exit '
            '0, instead of gating. Run once to adopt the gate on an existing '
            'codebase.',
      )
      ..addFlag(
        'include-tests',
        negatable: false,
        help: 'Scan test code (test/, integration_test/, test_driver/) for '
            'duplication. Tests are left out of duplicate detection by '
            'default; every other check always covers them.',
      )
      ..addOption(
        'min-block-size',
        help: 'Minimum duplicate token block size. Defaults to the '
            'configured value, else $defaultDuplicateBlockSize.',
      )
      ..addOption(
        'max-complexity',
        help: 'Maximum cyclomatic complexity before a function is reported. '
            'Defaults to the configured value, else $defaultMaxComplexity.',
      )
      ..addFlag(
        'report-unused-ignores',
        negatable: false,
        help: 'Emit an info-level unused-ignore finding for every '
            "'dallow-ignore' comment that suppressed nothing (a stale "
            'directive). Off by default to keep output quiet.',
      )
      ..addFlag(
        'allow-unresolved',
        negatable: false,
        help: 'Analyse even when some files or imports could not be resolved '
            '(normally a missing `pub get`). The gaps are reported as '
            'unresolved-source warnings instead of aborting; dead-code and '
            'circular-import results may be wrong in their vicinity.',
      )
      ..addFlag(
        'recursive',
        abbr: 'r',
        negatable: false,
        help: 'Scan every member package of a monorepo (melos / pub workspace '
            '/ nested pubspecs) in one run, aggregating the results. Findings '
            'are attributed to their package. melos package globs support '
            '*, **, ?, and {a,b} brace alternation; any other syntax is '
            'rejected rather than silently matching nothing.',
      );
  }

  Set<Check> get checks;

  @override
  Future<int> run() async {
    try {
      return await _run();
    } on _UsageError catch (e) {
      return _fail(e.message, _ExitCode.usage);
    } on ConfigException catch (e) {
      return _fail(e.message, _ExitCode.usage);
    } on GateException catch (e) {
      return _fail(e.message, _ExitCode.usage);
    } on UnsupportedGlobException catch (e) {
      return _fail('$e', _ExitCode.usage);
    } on SdkNotFoundException catch (e) {
      return _fail(e.message, _ExitCode.sdkNotFound);
    } on UnresolvedSourceException catch (e) {
      return _fail(e.message, _ExitCode.unresolvedSource);
    }
  }

  int _fail(String message, int exitCode) {
    stderr.writeln(message);
    return exitCode;
  }

  Future<int> _run() async {
    final root = _root();
    final explicitConfig = _explicitConfig();
    final rootConfig = explicitConfig ?? DallowConfig.forPackage(root);
    final overrides = _overrides();

    final findings = (argResults!['recursive'] as bool)
        ? await _analyzeWorkspace(root, explicitConfig, overrides)
        : await analyze(
            root,
            checks: checks,
            allowUnresolved: _allowUnresolved,
            config: rootConfig.overriddenBy(
              maxCycleSize: overrides.maxCycleSize,
              minBlockSize: overrides.minBlockSize,
              maxComplexity: overrides.maxComplexity,
              reportGenerated: overrides.reportGenerated,
              duplicationIncludesTests: overrides.duplicationIncludesTests,
            ),
          );

    // --write-baseline short-circuits the gate: capture all current findings
    // and exit 0, regardless of --changed-since / --baseline.
    final writeBaseline = argResults!['write-baseline'] as String?;
    if (writeBaseline != null) return _writeBaseline(writeBaseline, findings);

    final gated = await _applyGate(findings, root);
    final format = ReportFormat.values.byName(argResults!['format'] as String);
    stdout.writeln(Reporter(format).render(gated));
    return exitCodeFor(gated, failOn: _failOn(rootConfig));
  }

  /// The package or workspace directory named on the command line.
  String _root() {
    final rest = argResults!.rest;
    final root = p.normalize(p.absolute(rest.isEmpty ? '.' : rest.first));
    if (!Directory(root).existsSync()) {
      throw _UsageError('No such directory: $root');
    }
    return root;
  }

  bool get _allowUnresolved => argResults!['allow-unresolved'] as bool;

  /// The settings given as flags, each null when its flag is absent so the
  /// configured value applies.
  _Overrides _overrides() => _Overrides(
        maxCycleSize: _threshold(
          'max-cycle-size',
          minimum: minCycleSize,
          belowMinimum: 'the smallest possible cycle; a lower value would '
              'skip every cycle and disable the check',
        ),
        minBlockSize: _threshold(
          'min-block-size',
          minimum: minDuplicateBlockSize,
          belowMinimum: 'smaller matches are too noisy to gate reliably',
        ),
        maxComplexity: _threshold(
          'max-complexity',
          minimum: minComplexityThreshold,
        ),
        reportGenerated: _enabledOrNull('include-generated'),
        duplicationIncludesTests: _enabledOrNull('include-tests'),
      );

  /// The integer given for [option], or null when the option is absent.
  int? _threshold(
    String option, {
    required int minimum,
    String? belowMinimum,
  }) {
    final raw = argResults![option] as String?;
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null) {
      throw _UsageError('--$option must be an integer: $raw');
    }
    if (value < minimum) {
      final reason = belowMinimum == null ? '' : ' ($belowMinimum)';
      throw _UsageError('--$option must be at least $minimum$reason.');
    }
    return value;
  }

  Future<List<Finding>> _analyzeWorkspace(
    String root,
    DallowConfig? explicitConfig,
    _Overrides overrides,
  ) {
    final discovery = discoverWorkspace(root);
    if (discovery.packageRoots.isEmpty) {
      throw _UsageError(
        'No packages found under $root. Looked for melos.yaml packages, a '
        'pub workspace (pubspec.yaml with a workspace: list), then any '
        'nested pubspec.yaml.',
      );
    }
    // Informational, on stderr so stdout stays clean for json/markdown.
    stderr.writeln(
      'Scanning ${discovery.packageRoots.length} packages '
      '(${discovery.strategy.name}).',
    );
    return analyzeWorkspace(
      root,
      checks: checks,
      maxCycleSize: overrides.maxCycleSize,
      minBlockSize: overrides.minBlockSize,
      maxComplexity: overrides.maxComplexity,
      allowUnresolved: _allowUnresolved,
      reportGenerated: overrides.reportGenerated,
      duplicationIncludesTests: overrides.duplicationIncludesTests,
      config: explicitConfig,
      discovery: discovery,
    );
  }

  int _writeBaseline(String path, List<Finding> findings) {
    File(path).writeAsStringSync(encodeBaseline(findings));
    stderr.writeln(
      'Wrote baseline with ${findings.length} finding(s) to $path',
    );
    return _ExitCode.success;
  }

  /// True when the on/off [flag] was passed, else null so the configured
  /// value applies.
  bool? _enabledOrNull(String flag) =>
      (argResults![flag] as bool) ? true : null;

  /// The configuration named by `--config`, or null when the flag is absent
  /// and each package's own `dallow.yaml` applies.
  DallowConfig? _explicitConfig() {
    final path = argResults!['config'] as String?;
    return path == null ? null : DallowConfig.fromFile(path);
  }

  /// The gate threshold: the `--fail-on` flag, else the configured value,
  /// else `error`.
  FailOn _failOn(DallowConfig config) {
    final flag = argResults!['fail-on'] as String?;
    if (flag != null) return FailOn.values.byName(flag);
    return config.failOn ?? FailOn.error;
  }

  /// Applies the PR-gate filters — inline `dallow-ignore` suppression, then
  /// `--changed-since`, then `--baseline` — in sequence. All are pure keep/drop
  /// predicates, so the survivor set is order-independent; suppression runs
  /// *first*, against the raw findings, so an unused-ignore report reflects
  /// directives that genuinely matched nothing rather than ones whose finding a
  /// later filter had already dropped.
  Future<List<Finding>> _applyGate(List<Finding> findings, String root) async {
    final filters = <FindingFilter>[];

    final suppressions = const SuppressionScanner().scan(root);
    filters.add(suppressions.apply);

    final changedSince = argResults!['changed-since'] as String?;
    if (changedSince != null) {
      final changed = await changedFilesSince(changedSince, packageRoot: root);
      filters.add(changedSinceFilter(changed));
    }

    final baselinePath = argResults!['baseline'] as String?;
    if (baselinePath != null) {
      final file = File(baselinePath);
      if (!file.existsSync()) {
        throw GateException('No such baseline file: $baselinePath');
      }
      filters.add(baselineFilter(Baseline.parse(file.readAsStringSync())));
    }

    final gated = applyFilters(findings, filters);
    if (argResults!['report-unused-ignores'] as bool) {
      return [...gated, ...suppressions.unusedFindings];
    }
    return gated;
  }
}

class _AnalyzeCommand extends _CheckCommand {
  @override
  String get name => 'analyze';

  @override
  String get description => 'Run every check (the default).';

  @override
  Set<Check> get checks => Check.values.toSet();
}

class _DeadCodeCommand extends _CheckCommand {
  @override
  String get name => 'dead-code';

  @override
  String get description => 'Find symbols unreachable from any entrypoint.';

  @override
  Set<Check> get checks => {Check.deadCode};
}

class _DepsCommand extends _CheckCommand {
  @override
  String get name => 'deps';

  @override
  String get description => 'Check dependency hygiene against pubspec.yaml.';

  @override
  Set<Check> get checks => {Check.dependencies};
}

class _CircularCommand extends _CheckCommand {
  @override
  String get name => 'circular';

  @override
  String get description => 'Detect circular imports between files.';

  @override
  Set<Check> get checks => {Check.circularImports};
}

class _DuplicationCommand extends _CheckCommand {
  @override
  String get name => 'duplication';

  @override
  String get description => 'Detect duplicated Dart token blocks.';

  @override
  Set<Check> get checks => {Check.duplication};
}

class _ComplexityCommand extends _CheckCommand {
  @override
  String get name => 'complexity';

  @override
  String get description => 'Measure cyclomatic complexity and project health.';

  @override
  Set<Check> get checks => {Check.complexity};
}
