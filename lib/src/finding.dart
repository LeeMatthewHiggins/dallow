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
  unusedIgnore('unused-ignore');

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

  /// Returns a copy of this finding attributed to [package].
  Finding withPackage(String package) => Finding(
        kind: kind,
        severity: severity,
        message: message,
        file: file,
        line: line,
        symbol: symbol,
        package: package,
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
