import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixture = p.absolute('test', 'fixtures', 'sample');

  group('dead-code check', () {
    test('flags a symbol unreachable from any entrypoint', () async {
      final findings = await analyze(fixture, checks: {Check.deadCode});
      final symbols = findings.map((f) => f.symbol).toSet();

      expect(symbols, contains('deadFunction'));
    });

    test('does not flag symbols reachable from the public API', () async {
      final findings = await analyze(fixture, checks: {Check.deadCode});
      final symbols = findings.map((f) => f.symbol).toSet();

      expect(symbols, isNot(contains('used')));
      expect(symbols, isNot(contains('runSample')));
    });
  });

  group('dependency check', () {
    test('flags imported-but-undeclared packages as errors', () async {
      final findings = await analyze(fixture, checks: {Check.dependencies});
      final missing = findings
          .where((f) => f.kind == CheckKind.missingDependency)
          .map((f) => f.symbol)
          .toSet();

      expect(missing, contains('collection'));
    });

    test('flags declared-but-unused dependencies', () async {
      final findings = await analyze(fixture, checks: {Check.dependencies});
      final unused = findings
          .where((f) => f.kind == CheckKind.unusedDependency)
          .map((f) => f.symbol)
          .toSet();

      expect(unused, contains('meta'));
    });
  });

  group('circular-import check', () {
    test('detects a mutual import cycle', () async {
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
}
