import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'dallow',
    'Codebase intelligence for Dart and Flutter.',
  )
    ..addCommand(_AnalyzeCommand())
    ..addCommand(_DeadCodeCommand())
    ..addCommand(_DepsCommand())
    ..addCommand(_CircularCommand())
    ..addCommand(_DuplicationCommand())
    ..addCommand(_ComplexityCommand());

  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}

abstract class _CheckCommand extends Command<int> {
  _CheckCommand() {
    argParser
      ..addOption(
        'format',
        abbr: 'f',
        allowed: ['console', 'json', 'markdown', 'sarif'],
        defaultsTo: 'console',
        help: 'Output format. `sarif` emits a SARIF 2.1.0 log for '
            'code-scanning platforms.',
      )
      ..addOption(
        'fail-on',
        allowed: ['error', 'warning', 'info', 'never'],
        defaultsTo: 'error',
        help: 'Lowest severity that causes a non-zero exit code.',
      )
      ..addOption(
        'max-cycle-size',
        help: 'Skip dependency cycles with more than this many files. Useful '
            'to ignore a known barrel mega-cycle while still catching small '
            'new cycles.',
      )
      ..addOption(
        'changed-since',
        help: 'Only report findings in files changed since this git ref '
            '(merge-base of <ref>...HEAD), e.g. origin/main or a SHA. '
            'Whole-package findings (no file / pubspec-level) are always '
            'kept. Requires the package to be inside a git work tree.',
      )
      ..addOption(
        'baseline',
        help: 'Suppress findings recorded in this JSON baseline file, so the '
            'gate fails only on findings introduced after it was written.',
      )
      ..addOption(
        'write-baseline',
        help: 'Write the current findings to this file as a baseline and exit '
            '0, instead of gating. Run once to adopt the gate on an existing '
            'codebase.',
      )
      ..addOption(
        'min-block-size',
        help: 'Minimum duplicate token block size. Defaults to '
            '$defaultDuplicateBlockSize.',
      )
      ..addOption(
        'max-complexity',
        help: 'Maximum cyclomatic complexity before a function is reported. '
            'Defaults to $defaultMaxComplexity.',
      )
      ..addFlag(
        'report-unused-ignores',
        negatable: false,
        help: 'Emit an info-level unused-ignore finding for every '
            "'dallow-ignore' comment that suppressed nothing (a stale "
            'directive). Off by default to keep output quiet.',
      );
  }

  Set<Check> get checks;

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final root = p.normalize(p.absolute(rest.isEmpty ? '.' : rest.first));
    if (!Directory(root).existsSync()) {
      stderr.writeln('No such directory: $root');
      return 64;
    }

    final maxCycleSizeRaw = argResults!['max-cycle-size'] as String?;
    final maxCycleSize =
        maxCycleSizeRaw == null ? null : int.tryParse(maxCycleSizeRaw);
    if (maxCycleSizeRaw != null && maxCycleSize == null) {
      stderr.writeln('--max-cycle-size must be an integer: $maxCycleSizeRaw');
      return 64;
    }
    if (maxCycleSize != null && maxCycleSize < minCycleSize) {
      stderr.writeln(
        '--max-cycle-size must be at least $minCycleSize (the smallest '
        'possible cycle); $maxCycleSize would skip every cycle and disable '
        'the check.',
      );
      return 64;
    }
    final minBlockSizeRaw = argResults!['min-block-size'] as String?;
    final minBlockSize =
        minBlockSizeRaw == null ? null : int.tryParse(minBlockSizeRaw);
    if (minBlockSizeRaw != null && minBlockSize == null) {
      stderr.writeln('--min-block-size must be an integer: $minBlockSizeRaw');
      return 64;
    }
    if (minBlockSize != null && minBlockSize < minDuplicateBlockSize) {
      stderr.writeln(
        '--min-block-size must be at least $minDuplicateBlockSize; smaller '
        'matches are too noisy to gate reliably.',
      );
      return 64;
    }
    final maxComplexityRaw = argResults!['max-complexity'] as String?;
    final maxComplexity =
        maxComplexityRaw == null ? null : int.tryParse(maxComplexityRaw);
    if (maxComplexityRaw != null && maxComplexity == null) {
      stderr.writeln('--max-complexity must be an integer: $maxComplexityRaw');
      return 64;
    }
    if (maxComplexity != null && maxComplexity < minComplexityThreshold) {
      stderr.writeln(
        '--max-complexity must be at least $minComplexityThreshold.',
      );
      return 64;
    }

    final List<Finding> findings;
    try {
      findings = await analyze(
        root,
        checks: checks,
        maxCycleSize: maxCycleSize,
        minBlockSize: minBlockSize,
        maxComplexity: maxComplexity,
      );
    } on SdkNotFoundException catch (e) {
      stderr.writeln(e.message);
      return 69;
    }

    // --write-baseline short-circuits the gate: capture all current findings
    // and exit 0, regardless of --changed-since / --baseline.
    final writeBaseline = argResults!['write-baseline'] as String?;
    if (writeBaseline != null) {
      File(writeBaseline).writeAsStringSync(encodeBaseline(findings));
      stderr.writeln(
        'Wrote baseline with ${findings.length} finding(s) to $writeBaseline',
      );
      return 0;
    }

    final List<Finding> gated;
    try {
      gated = await _applyGate(findings, root);
    } on GateException catch (e) {
      stderr.writeln(e.message);
      return 64;
    }

    final format = ReportFormat.values.byName(argResults!['format'] as String);
    stdout.writeln(Reporter(format).render(gated));

    final failOn = FailOn.values.byName(argResults!['fail-on'] as String);
    return exitCodeFor(gated, failOn: failOn);
  }

  /// Applies the PR-gate filters — inline `dallow-ignore` suppression, then
  /// `--changed-since`, then `--baseline` — in sequence. All are pure keep/drop
  /// predicates, so the survivor set is order-independent; suppression runs
  /// *first*, against the raw findings, so an unused-ignore report reflects
  /// directives that genuinely matched nothing rather than ones whose finding a
  /// later filter had already dropped.
  Future<List<Finding>> _applyGate(List<Finding> findings, String root) async {
    final filters = <FindingFilter>[];

    final suppressions = const SuppressionScanner().scan(root);
    filters.add(suppressions.apply);

    final changedSince = argResults!['changed-since'] as String?;
    if (changedSince != null) {
      final changed = await changedFilesSince(changedSince, packageRoot: root);
      filters.add(changedSinceFilter(changed));
    }

    final baselinePath = argResults!['baseline'] as String?;
    if (baselinePath != null) {
      final file = File(baselinePath);
      if (!file.existsSync()) {
        throw GateException('No such baseline file: $baselinePath');
      }
      filters.add(baselineFilter(Baseline.parse(file.readAsStringSync())));
    }

    final gated = applyFilters(findings, filters);
    if (argResults!['report-unused-ignores'] as bool) {
      return [...gated, ...suppressions.unusedFindings];
    }
    return gated;
  }
}

class _AnalyzeCommand extends _CheckCommand {
  @override
  String get name => 'analyze';

  @override
  String get description => 'Run every check (the default).';

  @override
  Set<Check> get checks => Check.values.toSet();
}

class _DeadCodeCommand extends _CheckCommand {
  @override
  String get name => 'dead-code';

  @override
  String get description => 'Find symbols unreachable from any entrypoint.';

  @override
  Set<Check> get checks => {Check.deadCode};
}

class _DepsCommand extends _CheckCommand {
  @override
  String get name => 'deps';

  @override
  String get description => 'Check dependency hygiene against pubspec.yaml.';

  @override
  Set<Check> get checks => {Check.dependencies};
}

class _CircularCommand extends _CheckCommand {
  @override
  String get name => 'circular';

  @override
  String get description => 'Detect circular imports between files.';

  @override
  Set<Check> get checks => {Check.circularImports};
}

class _DuplicationCommand extends _CheckCommand {
  @override
  String get name => 'duplication';

  @override
  String get description => 'Detect duplicated Dart token blocks.';

  @override
  Set<Check> get checks => {Check.duplication};
}

class _ComplexityCommand extends _CheckCommand {
  @override
  String get name => 'complexity';

  @override
  String get description => 'Measure cyclomatic complexity and project health.';

  @override
  Set<Check> get checks => {Check.complexity};
}
