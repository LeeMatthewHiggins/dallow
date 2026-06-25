/// Codebase intelligence for Dart and Flutter: reachability-based dead-code
/// detection, dependency hygiene, and circular-import analysis.
library;

export 'src/analysis.dart';
export 'src/checks/circular_import_check.dart' show minCycleSize;
export 'src/checks/complexity_check.dart'
    show defaultMaxComplexity, minComplexityThreshold;
export 'src/checks/duplication_check.dart'
    show defaultDuplicateBlockSize, minDuplicateBlockSize;
export 'src/finding.dart';
export 'src/gate.dart';
export 'src/gate/baseline.dart';
export 'src/gate/diff_filter.dart';
export 'src/gate/finding_filter.dart';
export 'src/gate/fingerprint.dart';
export 'src/gate/suppression.dart';
export 'src/graph/code_graph.dart';
export 'src/report/reporter.dart';
export 'src/report/sarif_reporter.dart';
