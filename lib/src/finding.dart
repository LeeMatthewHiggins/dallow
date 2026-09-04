/// The category of analysis that produced a [Finding].
enum CheckKind {
  deadCode('dead-code'),
  unusedDependency('unused-dependency'),
  missingDependency('missing-dependency'),
  misplacedDependency('misplaced-dependency'),
  circularImport('circular-import'),
  duplicateCode('duplicate-code'),
  highComplexity('high-complexity'),
  projectHealth('project-health'),
  unusedIgnore('unused-ignore'),
  unresolvedSource('unresolved-source');

  const CheckKind(this.id);

  /// Stable identifier used in machine-readable output.
  final String id;
}

/// The severity of a [Finding], driving the process exit code.
enum Severity {
  error,
  warning,
  info;

  String get label => name;
}

/// A single problem discovered during analysis.
class Finding {
  const Finding({
    required this.kind,
    required this.severity,
    required this.message,
    this.file,
    this.line,
    this.symbol,
    this.package,
    this.weight = 1,
  });

  final CheckKind kind;
  final Severity severity;
  final String message;

  /// Path relative to the analysed package root, when applicable.
  final String? file;
  final int? line;

  /// The named element the finding refers to, when applicable.
  final String? symbol;

  /// The member package this finding belongs to, as a path relative to the
  /// scanned workspace root (`.` for the root package). Set only in recursive
  /// (`--recursive`) runs; null for a single-package analysis, keeping that
  /// output unchanged.
  final String? package;

  /// How much this finding counts towards the project health score, relative
  /// to a plain finding of its severity. Most findings weigh 1; a duplicated
  /// block weighs its size in multiples of the minimum reportable block, so
  /// a copied 800-token function costs far more than a repeated import line.
  /// Not part of the serialised output.
  final double weight;

  /// Returns a copy of this finding attributed to [package].
  Finding withPackage(String package) => Finding(
        kind: kind,
        severity: severity,
        message: message,
        file: file,
        line: line,
        symbol: symbol,
        package: package,
        weight: weight,
      );

  Map<String, Object?> toJson() => {
        if (package != null) 'package': package,
        'kind': kind.id,
        'severity': severity.label,
        'message': message,
        if (file != null) 'file': file,
        if (line != null) 'line': line,
        if (symbol != null) 'symbol': symbol,
      };
}
