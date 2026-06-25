import 'dart:convert';

import 'package:dallow/src/finding.dart';
import 'package:dallow/src/report/reporter.dart';
import 'package:path/path.dart' as p;

/// Renders findings as a [SARIF 2.1.0](https://sarifweb.azurewebsites.net/) log
/// — the Static Analysis Results Interchange Format consumed by code-scanning
/// platforms (GitHub Advanced Security, Azure DevOps, …).
///
/// The log contains a single `run` whose `tool.driver` advertises **one rule
/// per [CheckKind]** (whether or not it fired) so the rule catalogue is stable
/// across runs, and whose `results` carry one entry per [Finding].
///
/// A `physicalLocation` is emitted **only when the finding has both a `file`
/// and a `line`**. GitHub code-scanning ingestion requires `region.startLine`
/// to place an annotation; a `physicalLocation` carrying an `artifactLocation`
/// but no `region` is not displayable and gets pinned to line 1. Rather than
/// invent that line, findings without a source line — whole-package signals
/// (no `file`) and `pubspec.yaml`-level dependency findings (`file` but no
/// `line`) — are emitted as valid results with **no `locations`** (the array
/// is optional in SARIF); the file they concern remains named in the result's
/// `message.text`, so nothing is silently dropped.
class SarifReporter implements Reporter {
  const SarifReporter();

  /// The published JSON Schema for SARIF 2.1.0.
  static const schemaUri = 'https://json.schemastore.org/sarif-2.1.0.json';

  /// Where a consumer can learn about the tool that produced the log.
  static const informationUri = 'https://github.com/LeeMatthewHiggins/dallow';

  @override
  String render(List<Finding> findings) {
    final log = <String, Object?>{
      r'$schema': schemaUri,
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'dallow',
              'informationUri': informationUri,
              'rules': [
                for (final kind in CheckKind.values) _rule(kind),
              ],
            },
          },
          'results': [
            for (final finding in findings) _result(finding),
          ],
        },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(log);
  }

  Map<String, Object?> _rule(CheckKind kind) => {
        'id': kind.id,
        'name': kind.name,
        'shortDescription': {'text': _ruleDescriptions[kind]!},
        'defaultConfiguration': {'level': _sarifLevel(_ruleSeverities[kind]!)},
      };

  Map<String, Object?> _result(Finding finding) => {
        'ruleId': finding.kind.id,
        'level': _sarifLevel(finding.severity),
        'message': {'text': finding.message},
        // A SARIF location is only displayable when it pins a line, so emit one
        // exclusively for findings that carry both a file and a line. See the
        // class doc comment for why file-only findings get no `locations`.
        if (finding.file != null && finding.line != null)
          'locations': [_location(finding)],
      };

  Map<String, Object?> _location(Finding finding) => {
        'physicalLocation': {
          'artifactLocation': {'uri': _uri(finding.file!)},
          'region': {'startLine': finding.line},
        },
      };

  /// SARIF artifact URIs are relative POSIX paths regardless of host OS.
  String _uri(String file) => p.posix.joinAll(p.split(file));
}

/// Maps a dallow [Severity] to a SARIF result/configuration `level`. SARIF has
/// no "info" level — its lowest non-suppressed level is `note`.
String _sarifLevel(Severity severity) {
  switch (severity) {
    case Severity.error:
      return 'error';
    case Severity.warning:
      return 'warning';
    case Severity.info:
      return 'note';
  }
}

/// The `defaultConfiguration.level` advertised for each rule, taken from the
/// severity its check emits. Findings still carry their own level; this only
/// seeds a consumer that has no per-result level.
const _ruleSeverities = <CheckKind, Severity>{
  CheckKind.deadCode: Severity.warning,
  CheckKind.unusedDependency: Severity.warning,
  CheckKind.missingDependency: Severity.error,
  CheckKind.misplacedDependency: Severity.warning,
  CheckKind.circularImport: Severity.warning,
  CheckKind.duplicateCode: Severity.warning,
};

/// A one-line `shortDescription` for each rule in the driver catalogue.
const _ruleDescriptions = <CheckKind, String>{
  CheckKind.deadCode: 'A symbol or member unreachable from any entrypoint.',
  CheckKind.unusedDependency:
      'A dependency declared in pubspec.yaml that is never imported.',
  CheckKind.missingDependency:
      'A package imported in code but absent from pubspec.yaml.',
  CheckKind.misplacedDependency:
      'A dependency declared in the wrong pubspec.yaml section.',
  CheckKind.circularImport: 'An import/export cycle between files.',
  CheckKind.duplicateCode: 'A duplicated block of Dart tokens.',
};
