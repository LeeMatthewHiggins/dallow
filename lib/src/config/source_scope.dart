import 'dart:convert';
import 'dart:io';

import 'package:dallow/src/config/dallow_config.dart';
import 'package:dallow/src/finding.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

abstract final class _Generated {
  /// File-name patterns of the code generators in common use: `build_runner`
  /// builders (json_serializable, drift, riverpod, …), freezed, auto_route,
  /// mockito, protobuf and flutter_gen.
  static const patterns = [
    '*.g.dart',
    '*.freezed.dart',
    '*.gr.dart',
    '*.mocks.dart',
    '*.pb.dart',
    '*.pbenum.dart',
    '*.pbjson.dart',
    '*.pbgrpc.dart',
    '*.pbserver.dart',
    '*.gen.dart',
  ];

  /// Matches the "generated, do not edit" banner generators write at the top
  /// of a file, in either word order.
  static final header = RegExp(
    r'generated\b.*\bdo\s+not\s+(manually\s+)?(modify|edit)|'
    r'\bdo\s+not\s+(manually\s+)?(modify|edit)\b.*generated',
    caseSensitive: false,
  );

  /// How many leading lines are searched for [header].
  static const headerLineLimit = 30;

  static const commentPrefix = '//';
}

abstract final class _Tests {
  /// The directories that hold test code in a Dart or Flutter package.
  static const directories = [
    'test/**',
    'integration_test/**',
    'test_driver/**',
  ];
}

/// Decides which files of one package a run reports on.
///
/// A file can be left out for two reasons: it matches an `exclude:` glob, or
/// it is generated code — recognised by file name ([DallowConfig] patterns plus
/// the built-in ones) or by a generated-code banner in its leading comment.
/// Left-out files still feed the symbol graph, so the code they reference
/// stays reachable; only findings located *in* them are dropped.
class SourceScope {
  SourceScope({required String root, required DallowConfig config})
      : _root = root,
        _reportGenerated = config.reportGenerated,
        _excluded = _PathMatcher(config.exclude),
        _duplicationExcluded = _PathMatcher([
          ...config.duplicationExclude,
          if (!config.duplicationIncludesTests) ..._Tests.directories,
        ]),
        _generatedByName = _PathMatcher([
          ..._Generated.patterns,
          ...config.generatedPatterns,
        ]);

  final String _root;
  final bool _reportGenerated;
  final _PathMatcher _excluded;
  final _PathMatcher _duplicationExcluded;
  final _PathMatcher _generatedByName;
  final Map<String, bool> _generatedCache = {};

  /// Whether the file at [relativePath] (relative to the package root) is
  /// generated code.
  bool isGenerated(String relativePath) => _generatedCache.putIfAbsent(
        relativePath,
        () =>
            _generatedByName.matches(relativePath) ||
            _hasGeneratedHeader(relativePath),
      );

  /// Whether findings located in [relativePath] are reported.
  bool reports(String relativePath) {
    if (_excluded.matches(relativePath)) return false;
    return _reportGenerated || !isGenerated(relativePath);
  }

  /// Whether [relativePath] takes part in duplicate detection. Test code is
  /// left out unless the configuration asks for it.
  bool scansForDuplication(String relativePath) =>
      reports(relativePath) && !_duplicationExcluded.matches(relativePath);

  /// Whether [finding] survives the scope. Findings with no source file, and
  /// `pubspec.yaml`-level ones, describe the package as a whole and are kept.
  bool reportsFinding(Finding finding) {
    final file = finding.file;
    if (file == null || !file.endsWith('.dart')) return true;
    return reports(file);
  }

  bool _hasGeneratedHeader(String relativePath) {
    final file = File(p.join(_root, relativePath));
    if (!file.existsSync()) return false;
    final List<String> lines;
    try {
      lines = const LineSplitter().convert(file.readAsStringSync());
    } on FileSystemException {
      return false;
    }
    for (final line in lines.take(_Generated.headerLineLimit)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith(_Generated.commentPrefix)) return false;
      if (_Generated.header.hasMatch(trimmed)) return true;
    }
    return false;
  }
}

/// Matches package-relative paths against a list of globs. A pattern without
/// a `/` is matched against the file name at any depth (`*.g.dart`); one with
/// a `/` is matched against the whole path (`lib/l10n/**`).
class _PathMatcher {
  _PathMatcher(List<String> patterns)
      : _byName = _compile(patterns.where((g) => !g.contains(_separator))),
        _byPath = _compile(patterns.where((g) => g.contains(_separator)));

  static const _separator = '/';

  final List<Glob> _byName;
  final List<Glob> _byPath;

  static List<Glob> _compile(Iterable<String> patterns) => [
        for (final pattern in patterns) Glob(pattern, context: p.posix),
      ];

  bool matches(String relativePath) {
    final posixPath = p.split(p.normalize(relativePath)).join(_separator);
    final name = p.posix.basename(posixPath);
    return _byName.any((glob) => glob.matches(name)) ||
        _byPath.any((glob) => glob.matches(posixPath));
  }
}
