import 'package:dallow/src/checks/circular_import_check.dart';
import 'package:dallow/src/checks/complexity_check.dart';
import 'package:dallow/src/checks/dead_code_check.dart';
import 'package:dallow/src/checks/dependency_check.dart';
import 'package:dallow/src/checks/duplication_check.dart';
import 'package:dallow/src/config/dallow_config.dart';
import 'package:dallow/src/config/source_scope.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';
import 'package:dallow/src/workspace/package_discovery.dart';
import 'package:path/path.dart' as p;

/// Thrown when the symbol graph has holes — files or directives the analyzer
/// could not resolve — and the caller has not opted in to analysing anyway.
/// Reachability results from such a graph are confidently wrong, so refusing
/// is the safe default.
class UnresolvedSourceException implements Exception {
  UnresolvedSourceException(this.problems);

  final List<ResolutionProblem> problems;

  static const _maxListed = 5;

  String get message {
    final listed = problems.take(_maxListed).map((p) => '  $p').join('\n');
    final more = problems.length > _maxListed
        ? '\n  (+${problems.length - _maxListed} more)'
        : '';
    return 'Could not resolve ${problems.length} source location(s); '
        'dead-code and import results would be unreliable:\n$listed$more\n'
        'Run `dart pub get` (or `flutter pub get`) in the package first. '
        'To analyse anyway and report the gaps as findings, pass '
        '--allow-unresolved.';
  }

  @override
  String toString() => message;
}

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

/// Runs the requested [checks] against the package rooted at [rootPath] — an
/// absolute path, or one relative to the current directory — and returns the
/// combined findings. The symbol graph is built at most once and
/// shared across the checks that need it.
///
/// Settings come from [config], or from the package's `dallow.yaml` when
/// [config] is omitted. An explicit [maxCycleSize], [minBlockSize],
/// [maxComplexity], [reportGenerated] or [duplicationIncludesTests] argument
/// overrides the configured
/// value. Throws [ConfigException] when the configuration file is invalid.
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
  bool allowUnresolved = false,
  bool? reportGenerated,
  bool? duplicationIncludesTests,
  DallowConfig? config,
}) async {
  final root = p.normalize(p.absolute(rootPath));
  final settings = (config ?? DallowConfig.forPackage(root)).overriddenBy(
    maxCycleSize: maxCycleSize,
    minBlockSize: minBlockSize,
    maxComplexity: maxComplexity,
    reportGenerated: reportGenerated,
    duplicationIncludesTests: duplicationIncludesTests,
  );
  final run = _AnalysisRun(
    root: root,
    checks: checks,
    settings: settings,
    allowUnresolved: allowUnresolved,
  );

  final findings = [...await run.graphFindings(), ...run.sourceFindings()];
  return run.withHealth(_applyRules(findings, settings.rules).toList());
}

/// One package's analysis: the requested checks, run under resolved settings.
class _AnalysisRun {
  _AnalysisRun({
    required this.root,
    required this.checks,
    required this.settings,
    required this.allowUnresolved,
  }) : scope = SourceScope(root: root, config: settings);

  final String root;
  final Set<Check> checks;
  final DallowConfig settings;
  final bool allowUnresolved;
  final SourceScope scope;

  ComplexityResult? _complexity;

  /// Findings of the checks that need the resolved symbol graph, which is
  /// built once and only when one of them is requested.
  Future<List<Finding>> graphFindings() async {
    if (!checks.any((c) => c.needsGraph)) return const [];

    final graph = await CodeGraph.build(root);
    if (graph.resolutionProblems.isNotEmpty && !allowUnresolved) {
      throw UnresolvedSourceException(graph.resolutionProblems);
    }
    return [
      ...graph.resolutionProblems.map(_unresolvedFinding),
      if (checks.contains(Check.deadCode))
        ...const DeadCodeCheck().run(graph).where(scope.reportsFinding),
      if (checks.contains(Check.circularImports))
        ...const CircularImportCheck()
            .run(graph, maxCycleSize: settings.maxCycleSize)
            .where(scope.reportsFinding),
      if (checks.contains(Check.complexity)) ..._complexityFindings(graph),
    ];
  }

  List<Finding> _complexityFindings(CodeGraph graph) {
    final result = const ComplexityCheck().run(
      graph,
      maxComplexity: settings.maxComplexity,
      include: scope.reports,
    );
    _complexity = result;
    return result.findings;
  }

  /// Findings of the checks that read source files and `pubspec.yaml`
  /// directly.
  List<Finding> sourceFindings() => [
        if (checks.contains(Check.dependencies))
          ...const DependencyCheck().run(
            root,
            ignored: settings.ignoredDependencies,
          ),
        if (checks.contains(Check.duplication))
          ...const DuplicationCheck().run(
            root,
            minBlockSize: settings.minBlockSize,
            include: scope.scansForDuplication,
          ),
      ];

  /// Appends the project health finding, scored from [findings], when the
  /// complexity check ran.
  List<Finding> withHealth(List<Finding> findings) {
    final complexity = _complexity;
    if (complexity == null) return findings;

    final health = complexity.healthFinding(
      otherFindings: findings.where(
        (f) => !_excludedFromHealth.contains(f.kind),
      ),
    );
    return [
      ...findings,
      ..._applyRules([health], settings.rules),
    ];
  }

  static const Set<CheckKind> _excludedFromHealth = {
    CheckKind.highComplexity,
    CheckKind.projectHealth,
    CheckKind.unresolvedSource,
  };
}

/// Applies the configured per-kind [rules]: a finding whose kind is switched
/// off is dropped, one with a severity override is reported at that severity,
/// and every other finding passes through unchanged.
Iterable<Finding> _applyRules(
  Iterable<Finding> findings,
  Map<CheckKind, RuleLevel> rules,
) sync* {
  for (final finding in findings) {
    final level = rules[finding.kind];
    if (level == null) {
      yield finding;
      continue;
    }
    final severity = level.severity;
    if (severity != null) yield finding.withSeverity(severity);
  }
}

Finding _unresolvedFinding(ResolutionProblem problem) => Finding(
      kind: CheckKind.unresolvedSource,
      severity: Severity.warning,
      message: 'Unresolved source (${problem.message}); dead-code and '
          'circular-import findings that depend on it may be wrong.',
      file: problem.relativePath,
      line: problem.line,
    );

/// Runs [analyze] against every member package discovered under [root] and
/// returns the aggregated findings, each tagged (via [Finding.withPackage])
/// with its package's path relative to [root] so results stay attributable.
///
/// Member packages are found with [discoverWorkspace] (melos globs, then a pub
/// `workspace:` list, then nested `pubspec.yaml` files). Packages are analysed
/// in sorted-path order and their findings concatenated, so a single
/// `exitCodeFor` call over the result honours `--fail-on` across every package.
///
/// Pass [discovery] to reuse a [WorkspaceDiscovery] already computed by the
/// caller (e.g. for an empty-workspace guard), so the filesystem walk runs once
/// per recursive run rather than twice. When omitted, discovery runs here.
///
/// Each package is analysed with [config] when given; otherwise with its own
/// `dallow.yaml`, falling back to the one at the workspace [root].
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
  bool allowUnresolved = false,
  bool? reportGenerated,
  bool? duplicationIncludesTests,
  DallowConfig? config,
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
      allowUnresolved: allowUnresolved,
      reportGenerated: reportGenerated,
      duplicationIncludesTests: duplicationIncludesTests,
      config: config ??
          DallowConfig.forPackage(packageRoot, fallbackRoot: normalisedRoot),
    );
    final relative = p.relative(packageRoot, from: normalisedRoot);
    final label = relative == '.' ? '.' : p.split(relative).join('/');
    for (final finding in findings) {
      aggregated.add(finding.withPackage(label));
    }
  }
  return aggregated;
}
