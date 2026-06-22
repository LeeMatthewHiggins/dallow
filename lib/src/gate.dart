import 'package:dallow/src/finding.dart';

/// The severity threshold at or above which a run fails (non-zero exit).
enum FailOn {
  error,
  warning,
  info,
  never;

  Severity? get threshold =>
      this == FailOn.never ? null : Severity.values[index];
}

/// Returns the process exit code for [findings] under the [failOn] policy:
/// `1` when any finding is at or above the threshold severity, else `0`.
///
/// [Severity] is ordered most-severe-first (`error` = 0), so a finding gates
/// when its index is `<=` the threshold index.
int exitCodeFor(List<Finding> findings, {required FailOn failOn}) {
  final threshold = failOn.threshold;
  if (threshold == null) return 0;
  final gated = findings.any((f) => f.severity.index <= threshold.index);
  return gated ? 1 : 0;
}
