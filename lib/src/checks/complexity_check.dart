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

  /// Measures every function in [graph]. A function is left out — of the
  /// findings and of the health score — when [include], given the
  /// package-relative path of its file, returns false.
  ComplexityResult run(
    CodeGraph graph, {
    int? maxComplexity,
    bool Function(String relativePath)? include,
  }) {
    final threshold = maxComplexity ?? defaultMaxComplexity;
    final functions = graph.functions
        .where((f) => include == null || include(f.relativePath))
        .toList(growable: false)
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

abstract final class _Health {
  static const maxScore = 100;
  static const maxComplexityPenalty = 60;
  static const maxFindingsPenalty = 40;

  /// Points lost for each percent of declared functions over the limit.
  static const pointsPerPercentOverLimit = 4;

  /// A function at twice the limit (an error) counts as this many.
  static const errorWeight = 2;

  static const percent = 100;

  static const errorSeverityWeight = 2.0;
  static const warningSeverityWeight = 1.0;
  static const infoSeverityWeight = 0.25;

  /// The lowest score that earns each grade, best first.
  static const grades = {'A': 90, 'B': 80, 'C': 70, 'D': 60};
  static const lowestGrade = 'F';
}

/// The complexity measurements of one package and the health score derived
/// from them.
///
/// The score starts at 100 and loses two capped penalties, both measured
/// against the number of *declared* functions (functions, methods and
/// constructors). Closures are left out of that count: a codebase full of
/// one-line callbacks would otherwise dilute every problem to nothing.
///
/// - **Complexity** (up to 60): 4 points for each percent of declared
///   functions over the limit, a function at twice the limit counting double.
/// - **Findings** (up to 40): 1 point for each weighted finding per hundred
///   declared functions.
class ComplexityResult {
  const ComplexityResult({
    required this.maxComplexity,
    required this.functions,
    required this.findings,
  });

  final int maxComplexity;
  final List<FunctionComplexity> functions;
  final List<Finding> findings;

  /// The declared functions, methods and constructors measured.
  int get declaredFunctionCount => functions.where((f) => !f.isClosure).length;

  Finding healthFinding({required Iterable<Finding> otherFindings}) {
    final score = healthScore(otherFindings: otherFindings);
    final weighted = _weightedFindings(otherFindings);

    return Finding(
      kind: CheckKind.projectHealth,
      severity: Severity.info,
      message: 'Project health score: $score/${_Health.maxScore} '
          '(grade ${gradeFor(score)}; $declaredFunctionCount function(s) '
          'analysed, ${findings.length} over the complexity limit; '
          'complexity penalty ${_complexityPenalty()}; findings penalty '
          '${_findingPenalty(otherFindings)} from '
          '${weighted.toStringAsFixed(1)} weighted findings).',
    );
  }

  int healthScore({required Iterable<Finding> otherFindings}) {
    final score = _Health.maxScore -
        _complexityPenalty() -
        _findingPenalty(otherFindings);
    return score.clamp(0, _Health.maxScore);
  }

  /// The letter grade for a health [score]: A from 90, B from 80, C from 70,
  /// D from 60, otherwise F.
  static String gradeFor(int score) {
    for (final MapEntry(key: grade, value: lowest) in _Health.grades.entries) {
      if (score >= lowest) return grade;
    }
    return _Health.lowestGrade;
  }

  int get _denominator => math.max(1, declaredFunctionCount);

  int _complexityPenalty() {
    final overLimit = findings.fold<int>(
      0,
      (sum, finding) =>
          sum + (finding.severity == Severity.error ? _Health.errorWeight : 1),
    );
    final percentOverLimit = overLimit * _Health.percent / _denominator;
    return math.min(
      _Health.maxComplexityPenalty,
      (percentOverLimit * _Health.pointsPerPercentOverLimit).round(),
    );
  }

  int _findingPenalty(Iterable<Finding> otherFindings) {
    final perHundredFunctions =
        _weightedFindings(otherFindings) * _Health.percent / _denominator;
    return math.min(_Health.maxFindingsPenalty, perHundredFunctions.round());
  }

  /// Findings summed by severity and by each finding's own [Finding.weight],
  /// so a copied 800-token function outweighs a repeated import line.
  double _weightedFindings(Iterable<Finding> otherFindings) {
    var weighted = 0.0;
    for (final finding in otherFindings) {
      final bySeverity = switch (finding.severity) {
        Severity.error => _Health.errorSeverityWeight,
        Severity.warning => _Health.warningSeverityWeight,
        Severity.info => _Health.infoSeverityWeight,
      };
      weighted += bySeverity * finding.weight;
    }
    return weighted;
  }
}
