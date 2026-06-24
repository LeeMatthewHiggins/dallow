import 'package:dallow/src/checks/circular_import_check.dart';
import 'package:dallow/src/checks/complexity_check.dart';
import 'package:dallow/src/checks/dead_code_check.dart';
import 'package:dallow/src/checks/dependency_check.dart';
import 'package:dallow/src/checks/duplication_check.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';
import 'package:dallow/src/workspace/package_discovery.dart';
import 'package:path/path.dart' as p;

/// The set of checks dallow knows how to run.
enum Check {
  deadCode,
  dependencies,
  circularImports,
  duplication,
  complexity;

  bool get needsGraph =>
      this == Check.deadCode ||
      this == Check.circularImports ||
      this == Check.complexity;
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
    Check.duplication,
  },
  int? maxCycleSize,
  int? minBlockSize,
  int? maxComplexity,
}) async {
  final findings = <Finding>[];
  ComplexityResult? complexityResult;

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
    if (checks.contains(Check.complexity)) {
      complexityResult = const ComplexityCheck().run(
        graph,
        maxComplexity: maxComplexity,
      );
      findings.addAll(complexityResult.findings);
    }
  }

  if (checks.contains(Check.dependencies)) {
    findings.addAll(const DependencyCheck().run(rootPath));
  }
  if (checks.contains(Check.duplication)) {
    findings.addAll(
      const DuplicationCheck().run(rootPath, minBlockSize: minBlockSize),
    );
  }
  if (complexityResult != null) {
    findings.add(
      complexityResult.healthFinding(
        otherFindings: findings.where(
          (f) =>
              f.kind != CheckKind.highComplexity &&
              f.kind != CheckKind.projectHealth,
        ),
      ),
    );
  }

  return findings;
}

/// Runs [analyze] against every member package discovered under [root] and
/// returns the aggregated findings, each tagged (via [Finding.withPackage])
/// with its package's path relative to [root] so results stay attributable.
///
/// Member packages are found with [discoverWorkspace] (melos globs, then a pub
/// `workspace:` list, then nested `pubspec.yaml` files). Packages are analysed
/// in sorted-path order and their findings concatenated, so a single
/// `exitCodeFor` call over the result honours `--fail-on` across every package.
/// Pass [discovery] to reuse a [WorkspaceDiscovery] already computed by the
/// caller (e.g. for an empty-workspace guard), so the filesystem walk runs once
/// per recursive run rather than twice. When omitted, discovery runs here.
Future<List<Finding>> analyzeWorkspace(
  String root, {
  Set<Check> checks = const {
    Check.deadCode,
    Check.dependencies,
    Check.circularImports,
    Check.duplication,
  },
  int? maxCycleSize,
  int? minBlockSize,
  int? maxComplexity,
  WorkspaceDiscovery? discovery,
}) async {
  final normalisedRoot = p.normalize(p.absolute(root));
  final resolved = discovery ?? discoverWorkspace(normalisedRoot);

  final aggregated = <Finding>[];
  for (final packageRoot in resolved.packageRoots) {
    final findings = await analyze(
      packageRoot,
      checks: checks,
      maxCycleSize: maxCycleSize,
      minBlockSize: minBlockSize,
      maxComplexity: maxComplexity,
    );
    final relative = p.relative(packageRoot, from: normalisedRoot);
    final label = relative == '.' ? '.' : p.split(relative).join('/');
    for (final finding in findings) {
      aggregated.add(finding.withPackage(label));
    }
  }
  return aggregated;
}
