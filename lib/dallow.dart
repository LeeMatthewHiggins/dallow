/// Codebase intelligence for Dart and Flutter: reachability-based dead-code
/// detection, dependency hygiene, circular-import analysis, duplicated-code
/// detection, and cyclomatic-complexity metrics with a project health score.
///
/// Call `analyze` for a single package or `analyzeWorkspace` for a monorepo,
/// narrow the result with a `FindingFilter`, render it with a `Reporter`, and
/// turn it into a process exit code with `exitCodeFor`.
library;

export 'src/analysis.dart';
export 'src/checks/circular_import_check.dart' show minCycleSize;
export 'src/checks/complexity_check.dart'
    show defaultMaxComplexity, minComplexityThreshold;
export 'src/checks/duplication_check.dart'
    show defaultDuplicateBlockSize, minDuplicateBlockSize;
export 'src/config/dallow_config.dart';
export 'src/config/localization_output.dart';
export 'src/config/source_scope.dart';
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
export 'src/version.dart';
export 'src/workspace/package_discovery.dart';
