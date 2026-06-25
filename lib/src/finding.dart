/// The category of analysis that produced a [Finding].
enum CheckKind {
  deadCode('dead-code'),
  unusedDependency('unused-dependency'),
  missingDependency('missing-dependency'),
  misplacedDependency('misplaced-dependency'),
  circularImport('circular-import'),
  duplicateCode('duplicate-code'),
  highComplexity('high-complexity'),
  projectHealth('project-health');

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
  });

  final CheckKind kind;
  final Severity severity;
  final String message;

  /// Path relative to the analysed package root, when applicable.
  final String? file;
  final int? line;

  /// The named element the finding refers to, when applicable.
  final String? symbol;

  Map<String, Object?> toJson() => {
        'kind': kind.id,
        'severity': severity.label,
        'message': message,
        if (file != null) 'file': file,
        if (line != null) 'line': line,
        if (symbol != null) 'symbol': symbol,
      };
}
