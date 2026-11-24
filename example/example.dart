// A CLI example prints its results.
// ignore_for_file: avoid_print

import 'package:dallow/dallow.dart';

/// Runs every dallow check against the package in the current directory and
/// prints the findings as a console report.
///
/// dallow is primarily a command-line tool (`dallow analyze`); this shows the
/// same analysis driven from Dart code.
Future<void> main() async {
  final findings = await analyze('.', checks: Check.values.toSet());

  print(Reporter(ReportFormat.console).render(findings));

  final exitCode = exitCodeFor(findings, failOn: FailOn.warning);
  print('A CI gate at --fail-on warning would exit $exitCode.');
}
