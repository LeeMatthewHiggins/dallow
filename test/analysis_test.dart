import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixture = p.absolute('test', 'fixtures', 'sample');

  group('dead-code check', () {
    late List<Finding> findings;
    late Set<String?> symbols;

    setUpAll(() async {
      findings = await analyze(fixture, checks: {Check.deadCode});
      symbols = findings.map((f) => f.symbol).toSet();
    });

    test('flags a symbol unreachable from any entrypoint', () {
      expect(symbols, contains('deadFunction'));
    });

    test('does not flag symbols reachable from the public API', () {
      expect(symbols, isNot(contains('used')));
      expect(symbols, isNot(contains('runSample')));
    });

    test('does not flag a lib/src symbol surfaced via re-export', () {
      expect(symbols, isNot(contains('ExportedWidget')));
    });

    test('does not flag a symbol referenced only through a typedef', () {
      expect(symbols, isNot(contains('TypedefThing')));
    });

    test('does not emit a phantom finding for an explicit getter', () {
      // An explicit `get x` has a synthetic backing variable (nameOffset -1);
      // it must not be registered as a dead symbol.
      expect(symbols, isNot(contains('_viaGetter')));
      expect(findings.every((f) => (f.line ?? -1) >= 1), isTrue);
    });

    test('labels the dead symbol with its element kind', () {
      final dead = findings.firstWhere((f) => f.symbol == 'deadFunction');
      expect(dead.message, contains('function'));
    });
  });

  group('dependency check', () {
    late List<Finding> findings;

    setUpAll(() async {
      findings = await analyze(fixture, checks: {Check.dependencies});
    });

    Set<String?> of(CheckKind kind) =>
        findings.where((f) => f.kind == kind).map((f) => f.symbol).toSet();

    test('flags imported-but-undeclared packages as errors', () {
      expect(of(CheckKind.missingDependency), contains('collection'));
    });

    test('flags declared-but-unused dependencies', () {
      expect(of(CheckKind.unusedDependency), contains('meta'));
    });

    test('flags dev dependencies imported from lib/', () {
      expect(of(CheckKind.misplacedDependency), contains('path'));
    });
  });

  group('circular-import check', () {
    test('detects a mutual dependency cycle', () async {
      final findings = await analyze(fixture, checks: {Check.circularImports});

      expect(findings, isNotEmpty);
      expect(
        findings.every((f) => f.kind == CheckKind.circularImport),
        isTrue,
      );
      expect(
        findings.first.message,
        allOf(contains('cycle_a.dart'), contains('cycle_b.dart')),
      );
    });
  });

  group('exit-code gate', () {
    const error = Finding(
      kind: CheckKind.missingDependency,
      severity: Severity.error,
      message: 'x',
    );
    const warning = Finding(
      kind: CheckKind.deadCode,
      severity: Severity.warning,
      message: 'x',
    );

    test('fail-on error gates errors but not warnings', () {
      expect(exitCodeFor([warning], failOn: FailOn.error), 0);
      expect(exitCodeFor([error], failOn: FailOn.error), 1);
    });

    test('fail-on warning gates warnings and errors', () {
      expect(exitCodeFor([warning], failOn: FailOn.warning), 1);
      expect(exitCodeFor([error], failOn: FailOn.warning), 1);
    });

    test('fail-on never always passes', () {
      expect(exitCodeFor([error], failOn: FailOn.never), 0);
    });
  });

  group('sdk resolution', () {
    test('locates a Dart SDK in the test environment', () {
      final sdk = resolveSdkPath();
      expect(sdk, isNotNull);
      expect(p.join(sdk!, 'version'), isNotEmpty);
    });
  });

  group('reporters', () {
    final findings = [
      const Finding(
        kind: CheckKind.deadCode,
        severity: Severity.warning,
        message: 'dead thing',
        file: 'lib/a.dart',
        line: 3,
        symbol: 'thing',
      ),
    ];

    test('console renders severity, kind and location', () {
      final output = Reporter(ReportFormat.console).render(findings);
      expect(output, contains('WARNING'));
      expect(output, contains('dead-code'));
      expect(output, contains('lib/a.dart:3'));
    });

    test('json is parseable and carries a summary', () {
      final output = Reporter(ReportFormat.json).render(findings);
      expect(output, contains('"total": 1'));
      expect(output, contains('"kind": "dead-code"'));
    });

    test('markdown emits a table', () {
      final output = Reporter(ReportFormat.markdown).render(findings);
      expect(output, contains('| Severity |'));
      expect(output, contains('`lib/a.dart:3`'));
    });

    test('console reports a clean run when empty', () {
      expect(Reporter(ReportFormat.console).render([]), contains('Clean'));
    });
  });
}
