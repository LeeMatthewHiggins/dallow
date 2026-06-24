import 'dart:convert';

import 'package:dallow/src/finding.dart';
import 'package:dallow/src/report/sarif_reporter.dart';

/// The rendering format for a run's [Finding] list.
enum ReportFormat { console, json, markdown, sarif }

/// Renders findings in the requested [ReportFormat].
abstract class Reporter {
  factory Reporter(ReportFormat format) {
    switch (format) {
      case ReportFormat.console:
        return const _ConsoleReporter();
      case ReportFormat.json:
        return const _JsonReporter();
      case ReportFormat.markdown:
        return const _MarkdownReporter();
      case ReportFormat.sarif:
        return const SarifReporter();
    }
  }

  String render(List<Finding> findings);
}

class _ConsoleReporter implements Reporter {
  const _ConsoleReporter();

  @override
  String render(List<Finding> findings) {
    if (findings.isEmpty) return 'No findings. Clean.';

    final buffer = StringBuffer();
    for (final finding in findings) {
      final location = _location(finding);
      buffer.writeln(
        '${finding.severity.label.toUpperCase().padRight(7)} '
        '[${finding.kind.id}] $location${finding.message}',
      );
    }
    buffer.write(_summary(findings));
    return buffer.toString();
  }

  String _location(Finding finding) {
    if (finding.file == null) return '';
    final line = finding.line != null ? ':${finding.line}' : '';
    return '${finding.file}$line  ';
  }
}

class _JsonReporter implements Reporter {
  const _JsonReporter();

  @override
  String render(List<Finding> findings) {
    final counts = _counts(findings);
    return const JsonEncoder.withIndent('  ').convert({
      'summary': {
        'total': findings.length,
        'error': counts[Severity.error],
        'warning': counts[Severity.warning],
        'info': counts[Severity.info],
      },
      'findings': findings.map((f) => f.toJson()).toList(),
    });
  }
}

class _MarkdownReporter implements Reporter {
  const _MarkdownReporter();

  @override
  String render(List<Finding> findings) {
    final buffer = StringBuffer('# dallow report\n\n');
    if (findings.isEmpty) {
      buffer.write('No findings. Clean.\n');
      return buffer.toString();
    }

    buffer
      ..writeln('| Severity | Check | Location | Message |')
      ..writeln('| --- | --- | --- | --- |');
    for (final finding in findings) {
      final line = finding.line != null ? ':${finding.line}' : '';
      final location = finding.file != null ? '`${finding.file}$line`' : '';
      buffer.writeln(
        '| ${finding.severity.label} | ${finding.kind.id} | $location | '
        '${finding.message} |',
      );
    }
    buffer
      ..writeln()
      ..writeln(_summary(findings));
    return buffer.toString();
  }
}

Map<Severity, int> _counts(List<Finding> findings) {
  final counts = {for (final s in Severity.values) s: 0};
  for (final finding in findings) {
    counts[finding.severity] = counts[finding.severity]! + 1;
  }
  return counts;
}

String _summary(List<Finding> findings) {
  final counts = _counts(findings);
  return '${findings.length} findings '
      '(${counts[Severity.error]} errors, '
      '${counts[Severity.warning]} warnings, '
      '${counts[Severity.info]} info).';
}
