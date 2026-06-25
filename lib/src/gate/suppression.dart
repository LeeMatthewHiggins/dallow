import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/gate/finding_filter.dart';
import 'package:dallow/src/util/dart_files.dart';
import 'package:path/path.dart' as p;

/// The comment marker that introduces an inline suppression directive.
///
/// `// dallow-ignore` on a finding's line — or on the line directly above it —
/// suppresses that finding before the gate, so it neither prints nor affects
/// the exit code. Scope it to a single check with
/// `// dallow-ignore: <check-kind>` (a comma-separated list is allowed); an
/// unscoped directive suppresses every kind on its target line.
const ignoreMarker = 'dallow-ignore';

/// A single `dallow-ignore` directive parsed from a source comment.
///
/// A directive at comment-line `L` suppresses findings on line `L` (a trailing
/// same-line comment) and on line `L + 1` (a comment written on the line
/// above the finding) — the two natural places to annotate a finding.
class IgnoreDirective {
  IgnoreDirective({
    required this.file,
    required this.line,
    required this.kinds,
  });

  /// Package-relative path (normalised) of the file the comment lives in,
  /// matching the form a [Finding.file] uses.
  final String file;

  /// 1-based line the comment sits on.
  final int line;

  /// The check kinds this directive suppresses, or `null` for an unscoped
  /// directive that suppresses every kind. A non-null **empty** set is a
  /// scoped directive whose named kinds were all unrecognised — it matches
  /// nothing (and so will surface as an unused ignore).
  final Set<CheckKind>? kinds;

  /// Whether this directive suppresses [finding].
  bool suppresses(Finding finding) {
    final findingLine = finding.line;
    final findingFile = finding.file;
    if (findingLine == null || findingFile == null) return false;
    if (p.normalize(findingFile) != file) return false;
    // Same line, or the directive is on the line directly above the finding.
    if (findingLine != line && findingLine != line + 1) return false;
    final scoped = kinds;
    if (scoped == null) return true;
    return scoped.contains(finding.kind);
  }
}

/// The directives discovered in a package, and the keep/drop filter they form.
///
/// [apply] is a [FindingFilter]: it drops every suppressed finding and records
/// which directives matched, so [unused] / [unusedFindings] can report the
/// directives that suppressed nothing.
class Suppressions {
  Suppressions(this.directives);

  /// Every directive parsed from the package, in file/line order.
  final List<IgnoreDirective> directives;

  final Set<IgnoreDirective> _used = {};

  bool get isEmpty => directives.isEmpty;

  /// Drops the findings suppressed by any directive, keeping the rest in order.
  /// Run this against the *raw* findings (before `--changed-since`/`--baseline`)
  /// so that [unused] reflects directives that genuinely matched nothing.
  List<Finding> apply(List<Finding> findings) {
    final survivors = <Finding>[];
    for (final finding in findings) {
      final match = directives.firstWhereOrNull((d) => d.suppresses(finding));
      if (match == null) {
        survivors.add(finding);
      } else {
        _used.add(match);
      }
    }
    return survivors;
  }

  /// Directives that suppressed nothing in the most recent [apply]. A stale
  /// `dallow-ignore` left behind after the finding it silenced was fixed.
  List<IgnoreDirective> get unused => [
        for (final d in directives)
          if (!_used.contains(d)) d
      ];

  /// [unused] rendered as info-level `unused-ignore` findings, so a stale
  /// suppression can itself be surfaced (and, under `--fail-on info`, gated).
  List<Finding> get unusedFindings => [
        for (final d in unused)
          Finding(
            kind: CheckKind.unusedIgnore,
            severity: Severity.info,
            message: _unusedMessage(d),
            file: d.file,
            line: d.line,
          ),
      ];

  static String _unusedMessage(IgnoreDirective d) {
    final kinds = d.kinds;
    final String scope;
    if (kinds == null) {
      scope = '';
    } else if (kinds.isEmpty) {
      scope = ' for an unrecognised check';
    } else {
      scope = ' for ${kinds.map((k) => k.id).join(', ')}';
    }
    return "Unused 'dallow-ignore' directive$scope; it suppressed no finding.";
  }
}

/// A [FindingFilter] over [suppressions] (its [Suppressions.apply]). Provided
/// for symmetry with `baselineFilter`/`changedSinceFilter`; callers that also
/// want [Suppressions.unused] should hold the instance and pass `.apply`.
FindingFilter suppressionFilter(Suppressions suppressions) =>
    suppressions.apply;

/// Scans a package's Dart sources for [ignoreMarker] directives, using the
/// analyzer's own comment tokens rather than a blind whole-file regex.
class SuppressionScanner {
  const SuppressionScanner();

  /// Parses every `dallow-ignore` directive under [rootPath]. [rootPath] may be
  /// a directory (the package) or a single `.dart` file.
  Suppressions scan(String rootPath) {
    final sourceRoot = _sourceRoot(rootPath);
    final directives = <IgnoreDirective>[];
    for (final path in _dartFiles(rootPath)) {
      final relative = p.normalize(p.relative(path, from: sourceRoot));
      directives.addAll(_scanFile(path, relative));
    }
    return Suppressions(directives);
  }

  List<IgnoreDirective> _scanFile(String path, String relative) {
    final content = File(path).readAsStringSync();
    final parsed = parseString(
      content: content,
      featureSet: FeatureSet.latestLanguageVersion(),
      path: path,
      throwIfDiagnostics: false,
    );

    final directives = <IgnoreDirective>[];
    Token? token = parsed.unit.beginToken;
    while (token != null) {
      Token? comment = token.precedingComments;
      while (comment is CommentToken) {
        final kinds = _parseDirective(comment.lexeme);
        if (!identical(kinds, _notADirective)) {
          final line = parsed.lineInfo.getLocation(comment.offset).lineNumber;
          directives.add(
            IgnoreDirective(
              file: relative,
              line: line,
              kinds: kinds as Set<CheckKind>?,
            ),
          );
        }
        comment = comment.next;
      }
      if (token.isEof) break;
      token = token.next;
    }
    return directives;
  }

  /// Sentinel distinguishing "not a directive" from "unscoped directive"
  /// (both would otherwise be `null`).
  static const Object _notADirective = Object();

  /// Returns `null` for an unscoped directive, a (possibly empty) set for a
  /// scoped one, or the [_notADirective] sentinel when [lexeme] is an ordinary
  /// comment.
  Object? _parseDirective(String lexeme) {
    final body = _commentBody(lexeme).trim();
    if (!body.startsWith(ignoreMarker)) return _notADirective;
    final after = body.substring(ignoreMarker.length);
    if (after.isEmpty) return null; // bare `// dallow-ignore`
    final first = after[0];
    if (first == ':') {
      final kinds = <CheckKind>{};
      for (final part in after.substring(1).split(',')) {
        // Accept a trailing reason after the kind: `dead-code keeping for API`.
        final id = part.trim().split(RegExp(r'\s')).first;
        final kind = _kindById(id);
        if (kind != null) kinds.add(kind);
      }
      return kinds; // scoped (empty when every named kind was unrecognised)
    }
    // `dallow-ignore <reason>` is unscoped; `dallow-ignored`/`-foo` is not.
    if (first.trim().isEmpty) return null;
    return _notADirective;
  }

  String _commentBody(String lexeme) {
    if (lexeme.startsWith('/*')) {
      var body = lexeme.substring(2);
      if (body.endsWith('*/')) body = body.substring(0, body.length - 2);
      return body;
    }
    var i = 0;
    while (i < lexeme.length && lexeme[i] == '/') {
      i++;
    }
    return lexeme.substring(i);
  }

  CheckKind? _kindById(String id) {
    for (final kind in CheckKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }

  List<String> _dartFiles(String rootPath) {
    final file = File(rootPath);
    if (file.existsSync() && rootPath.endsWith('.dart')) return [file.path];
    return listDartFiles(rootPath);
  }

  String _sourceRoot(String rootPath) {
    final file = File(rootPath);
    if (file.existsSync() && rootPath.endsWith('.dart')) {
      return p.dirname(file.path);
    }
    return rootPath;
  }
}

extension _FirstWhereOrNull<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
