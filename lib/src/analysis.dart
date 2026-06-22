import 'package:dallow/src/checks/circular_import_check.dart';
import 'package:dallow/src/checks/dead_code_check.dart';
import 'package:dallow/src/checks/dependency_check.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';

/// The set of checks dallow knows how to run.
enum Check {
  deadCode,
  dependencies,
  circularImports;

  bool get needsGraph => this != Check.dependencies;
}

/// Runs the requested [checks] against the package rooted at [rootPath] and
/// returns the combined findings. The symbol graph is built at most once and
/// shared across the checks that need it.
Future<List<Finding>> analyze(
  String rootPath, {
  Set<Check> checks = const {
    Check.deadCode,
    Check.dependencies,
    Check.circularImports,
  },
  int? maxCycleSize,
}) async {
  final findings = <Finding>[];

  if (checks.any((c) => c.needsGraph)) {
    final graph = await CodeGraph.build(rootPath);
    if (checks.contains(Check.deadCode)) {
      findings.addAll(const DeadCodeCheck().run(graph));
    }
    if (checks.contains(Check.circularImports)) {
      findings.addAll(
        const CircularImportCheck().run(graph, maxCycleSize: maxCycleSize),
      );
    }
  }

  if (checks.contains(Check.dependencies)) {
    findings.addAll(const DependencyCheck().run(rootPath));
  }

  return findings;
}
