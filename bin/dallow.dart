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
    ..addCommand(_CircularCommand());

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
        allowed: ['console', 'json', 'markdown'],
        defaultsTo: 'console',
        help: 'Output format.',
      )
      ..addOption(
        'fail-on',
        allowed: ['error', 'warning', 'info', 'never'],
        defaultsTo: 'error',
        help: 'Lowest severity that causes a non-zero exit code.',
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

    final findings = await analyze(root, checks: checks);

    final format = ReportFormat.values.byName(argResults!['format'] as String);
    stdout.writeln(Reporter(format).render(findings));

    return _exitCode(findings, argResults!['fail-on'] as String);
  }

  int _exitCode(List<Finding> findings, String failOn) {
    if (failOn == 'never') return 0;
    final threshold = Severity.values.byName(failOn);
    final gated = findings.any((f) => f.severity.index <= threshold.index);
    return gated ? 1 : 0;
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
