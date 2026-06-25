import 'dart:math' as math;

import 'package:dallow/src/finding.dart';
import 'package:dallow/src/graph/code_graph.dart';

/// The smallest useful cyclomatic complexity threshold.
const minComplexityThreshold = 1;

/// Default maximum cyclomatic complexity before a function is reported.
const defaultMaxComplexity = 10;

/// Reports function-like bodies whose cyclomatic complexity is over the
/// configured threshold, and computes the aggregate project health score.
class ComplexityCheck {
  const ComplexityCheck();

  ComplexityResult run(CodeGraph graph, {int? maxComplexity}) {
    final threshold = maxComplexity ?? defaultMaxComplexity;
    final functions = graph.functions.toList(growable: false)
      ..sort((a, b) {
        final byFile = a.relativePath.compareTo(b.relativePath);
        if (byFile != 0) return byFile;
        return a.line.compareTo(b.line);
      });

    final findings = <Finding>[];
    for (final function in functions) {
      if (function.complexity <= threshold) continue;
      final severity = function.complexity >= threshold * 2
          ? Severity.error
          : Severity.warning;
      findings.add(
        Finding(
          kind: CheckKind.highComplexity,
          severity: severity,
          message: "Function '${function.symbol}' has cyclomatic complexity "
              '${function.complexity}; maximum is $threshold.',
          file: function.relativePath,
          line: function.line,
          symbol: function.symbol,
        ),
      );
    }

    return ComplexityResult(
      maxComplexity: threshold,
      functions: functions,
      findings: findings,
    );
  }
}

class ComplexityResult {
  const ComplexityResult({
    required this.maxComplexity,
    required this.functions,
    required this.findings,
  });

  final int maxComplexity;
  final List<FunctionComplexity> functions;
  final List<Finding> findings;

  Finding healthFinding({required Iterable<Finding> otherFindings}) {
    final score = healthScore(otherFindings: otherFindings);
    final analysed = functions.length;
    final complexityPenalty = _complexityPenalty();
    final findingPenalty = _findingPenalty(otherFindings);

    return Finding(
      kind: CheckKind.projectHealth,
      severity: Severity.info,
      message: 'Project health score: $score/100 '
          '($analysed function(s) analysed; complexity penalty '
          '$complexityPenalty; findings penalty $findingPenalty).',
    );
  }

  int healthScore({required Iterable<Finding> otherFindings}) {
    final score = 100 - _complexityPenalty() - _findingPenalty(otherFindings);
    return score.clamp(0, 100);
  }

  int _complexityPenalty() {
    if (functions.isEmpty) return 0;
    final excess = functions.fold<int>(
      0,
      (sum, function) => sum + math.max(0, function.complexity - maxComplexity),
    );
    return math.min(60, (excess / functions.length * 3).round());
  }

  int _findingPenalty(Iterable<Finding> otherFindings) {
    var weighted = 0.0;
    for (final finding in otherFindings) {
      weighted += switch (finding.severity) {
        Severity.error => 2,
        Severity.warning => 1,
        Severity.info => 0.25,
      };
    }
    final denominator = math.max(1, functions.length);
    return math.min(40, (weighted / denominator * 5).round());
  }
}
