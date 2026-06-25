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

    test('flags a dead extension type and labels it', () {
      expect(symbols, contains('DeadId'));
      final dead = findings.firstWhere((f) => f.symbol == 'DeadId');
      expect(dead.message, contains('extension type'));
    });
  });

  group('member-level dead-code', () {
    late List<Finding> findings;
    late Set<String?> symbols;

    setUpAll(() async {
      findings = await analyze(fixture, checks: {Check.deadCode});
      symbols = findings.map((f) => f.symbol).toSet();
    });

    test('flags an unused private method of a public class', () {
      const symbol = 'ExportedWidget._unusedInternal';
      expect(symbols, contains(symbol));
      final dead = findings.firstWhere((f) => f.symbol == symbol);
      expect(dead.message, contains('method'));
    });

    test('flags an unused private method of an internal class', () {
      expect(symbols, contains('InternalService._unusedHelper'));
    });

    test('flags an unused public method of an internal (lib/src) class', () {
      expect(symbols, contains('InternalService.unusedPublicOnInternal'));
    });

    test('does not flag a used private method', () {
      expect(symbols, isNot(contains('InternalService._multiply')));
      expect(symbols, isNot(contains('ExportedWidget._decorate')));
    });

    test('does not flag a private field read internally', () {
      expect(symbols, isNot(contains('InternalService._seed')));
      expect(symbols, isNot(contains('ExportedWidget._suffix')));
      expect(symbols, isNot(contains('_Circle.radius')));
    });

    test('does not flag a public member of a public-API class', () {
      // `describe` is never called internally, but it is a public member of a
      // re-exported class, so it is part of the API surface.
      expect(symbols, isNot(contains('ExportedWidget.describe')));
      expect(symbols, isNot(contains('ExportedWidget.render')));
    });

    test('does not flag an @override member never called directly', () {
      // `_Circle.area` overrides `_Shape.area`; it may be dispatched through
      // the supertype, so neither the override nor the overridden member is
      // flagged.
      expect(symbols, isNot(contains('_Circle.area')));
      expect(symbols, isNot(contains('_Shape.area')));
    });

    test('does not flag a used public method of an internal class', () {
      expect(symbols, isNot(contains('InternalService.compute')));
    });

    test('does not flag a field initialised only via a this.x constructor', () {
      expect(symbols, isNot(contains('CtorOnlyField.label')));
    });

    test('does not flag a top-level symbol used only by a dead member', () {
      // Regression (F3 follow-up): top-level reachability must stay decoupled
      // from member reachability. `_unusedHelper` is itself dead and is the
      // ONLY referencer of the top-level `_usedOnlyByDeadMember`. The enclosing
      // (reachable) class records the top-level use — exactly as it did before
      // member analysis existed — so the top-level symbol stays alive. A
      // member-level false positive must never demote a top-level symbol.
      expect(symbols, isNot(contains('_usedOnlyByDeadMember')));
      // The dead member itself is still reported.
      expect(symbols, contains('InternalService._unusedHelper'));
    });

    test('does not redundantly report members of an already-dead type', () {
      // The enclosing class is itself reported dead, so listing its members
      // too would be noise.
      expect(symbols, contains('_DeadClass'));
      expect(symbols, isNot(contains('_DeadClass.orphanMethod')));
      // The representation field of a dead extension type is also not listed.
      expect(symbols, isNot(contains('DeadId.value')));
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

    test('does not flag a federated plugin implementation as unused', () {
      // google_maps_flutter_web is never imported, but its base plugin
      // google_maps_flutter is a declared dependency.
      expect(
        of(CheckKind.unusedDependency),
        isNot(contains('google_maps_flutter_web')),
      );
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

    test('skips cycles larger than maxCycleSize', () async {
      final findings = await analyze(
        fixture,
        checks: {Check.circularImports},
        maxCycleSize: 1,
      );

      expect(findings, isEmpty);
    });

    test('reports a cycle exactly at maxCycleSize (boundary)', () async {
      // The fixture cycle is 2 files: skipped at 1, reported at 2 — pinning
      // the `>` (not `>=`) comparison.
      final atTwo = await analyze(
        fixture,
        checks: {Check.circularImports},
        maxCycleSize: 2,
      );
      final atOne = await analyze(
        fixture,
        checks: {Check.circularImports},
        maxCycleSize: 1,
      );

      expect(atTwo, isNotEmpty);
      expect(atOne, isEmpty);
    });
  });

  group('duplication check', () {
    final duplicationFixture = p.absolute('test', 'fixtures', 'duplication');

    test('reports duplicated token blocks with every occurrence location',
        () async {
      final findings = await analyze(
        duplicationFixture,
        checks: {Check.duplication},
      );

      expect(findings, hasLength(1));
      final finding = findings.single;
      expect(finding.kind, CheckKind.duplicateCode);
      expect(finding.severity, Severity.warning);
      expect(finding.file, 'lib/duplicated.dart');
      expect(finding.line, 1);
      expect(finding.message, contains('lib/duplicated.dart:1'));
      expect(finding.message, contains('lib/duplicated.dart:10'));
    });

    test('does not report a non-duplicated file', () async {
      final findings = await analyze(
        p.join(duplicationFixture, 'lib', 'clean.dart'),
        checks: {Check.duplication},
      );

      expect(findings, isEmpty);
    });

    test('min-block-size filters small matches', () async {
      final smallFixture = p.join(duplicationFixture, 'lib', 'small.dart');

      final defaultFindings = await analyze(
        smallFixture,
        checks: {Check.duplication},
        minBlockSize: 4,
      );
      final filteredFindings = await analyze(
        smallFixture,
        checks: {Check.duplication},
        minBlockSize: 20,
      );

      expect(defaultFindings, isNotEmpty);
      expect(filteredFindings, isEmpty);
    });
  });

  group('complexity check', () {
    final complexityFixture = p.absolute('test', 'fixtures', 'complexity');
    final switchExpressionFixture =
        p.absolute('test', 'fixtures', 'switch_expression');

    test('reports functions above the complexity threshold', () async {
      final findings = await analyze(
        complexityFixture,
        checks: {Check.complexity},
        maxComplexity: 4,
      );

      final complexityFindings =
          findings.where((f) => f.kind == CheckKind.highComplexity).toList();
      expect(complexityFindings, hasLength(1));

      final finding = complexityFindings.single;
      expect(finding.severity, Severity.warning);
      expect(finding.file, 'lib/complexity.dart');
      expect(finding.line, 1);
      expect(finding.symbol, 'complexDecision');
      expect(finding.message, contains('complexity 6'));
      expect(finding.message, contains('maximum is 4'));
    });

    test('does not report functions at the threshold boundary', () async {
      final findings = await analyze(
        complexityFixture,
        checks: {Check.complexity},
        maxComplexity: 6,
      );

      expect(
        findings.where((f) => f.kind == CheckKind.highComplexity),
        isEmpty,
      );
    });

    test('does not report trivial functions as complex', () async {
      final findings = await analyze(
        p.join(complexityFixture, 'lib', 'trivial.dart'),
        checks: {Check.complexity},
        maxComplexity: 1,
      );

      expect(
        findings.where((f) => f.kind == CheckKind.highComplexity),
        isEmpty,
      );
    });

    test('counts switch expression arms as decision points', () async {
      final findings = await analyze(
        switchExpressionFixture,
        checks: {Check.complexity},
        maxComplexity: 1,
      );

      final finding = findings.singleWhere(
        (f) => f.kind == CheckKind.highComplexity,
      );
      expect(finding.file, 'lib/switch_expression.dart');
      expect(finding.line, 1);
      expect(finding.symbol, 'switchExpression');
      expect(finding.message, contains('complexity 7'));
    });

    test('pins the project health score formula', () async {
      final findings = await analyze(
        complexityFixture,
        checks: {Check.complexity},
        maxComplexity: 4,
      );

      final health = findings.singleWhere(
        (f) => f.kind == CheckKind.projectHealth,
      );
      expect(health.severity, Severity.info);
      expect(health.message, contains('Project health score: 97/100'));
      expect(health.message, contains('2 function(s) analysed'));
    });

    test('includes non-complexity findings in combined analysis health score',
        () async {
      final findings = await analyze(
        fixture,
        checks: {
          Check.deadCode,
          Check.dependencies,
          Check.circularImports,
          Check.duplication,
          Check.complexity,
        },
        maxComplexity: 10,
      );

      final health = findings.singleWhere(
        (f) => f.kind == CheckKind.projectHealth,
      );
      expect(health.message, contains('Project health score: 97/100'));
      expect(health.message, contains('24 function(s) analysed'));
      expect(health.message, contains('complexity penalty 0'));
      expect(health.message, contains('findings penalty 3'));
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
