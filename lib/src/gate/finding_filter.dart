import 'package:dallow/src/finding.dart';

/// A pure transformation over a finding list: the composable unit of the PR
/// gate. The `--changed-since`, `--baseline` (and, later, inline-suppression)
/// gates are each expressed as a [FindingFilter], applied in sequence between
/// `analyze()` and `exitCodeFor()`.
typedef FindingFilter = List<Finding> Function(List<Finding> findings);

/// Runs [findings] through [filters] left-to-right, threading each filter's
/// output into the next. An empty [filters] returns [findings] unchanged.
List<Finding> applyFilters(
  List<Finding> findings,
  Iterable<FindingFilter> filters,
) =>
    filters.fold(findings, (acc, filter) => filter(acc));

/// Raised when the gate cannot be applied — a bad git ref, a directory that is
/// not a git repository, or an unreadable/unsupported baseline file. Carries a
/// human-facing [message] suitable for stderr.
class GateException implements Exception {
  const GateException(this.message);

  final String message;

  @override
  String toString() => message;
}
