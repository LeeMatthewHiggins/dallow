/// Codebase intelligence for Dart and Flutter: reachability-based dead-code
/// detection, dependency hygiene, and circular-import analysis.
library;

export 'src/analysis.dart';
export 'src/checks/circular_import_check.dart' show minCycleSize;
export 'src/finding.dart';
export 'src/gate.dart';
export 'src/graph/code_graph.dart';
export 'src/report/reporter.dart';
