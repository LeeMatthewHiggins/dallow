import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixture = p.absolute('test', 'fixtures', 'generated');

  group('generated code is left out by default', () {
    late List<Finding> findings;
    late Set<String?> symbols;

    setUpAll(() async {
      findings = await analyze(fixture, checks: Check.values.toSet());
      symbols = findings.map((f) => f.symbol).toSet();
    });

    test('does not report dead code in a *.g.dart file', () {
      expect(symbols, isNot(contains(r'_$unusedGenerated')));
    });

    test('does not report dead code in a file with a generated banner', () {
      expect(symbols, isNot(contains('_bannerDead')));
    });

    test('keeps a symbol that only generated code references', () {
      expect(symbols, isNot(contains('_usedOnlyByGenerated')));
    });

    test('still reports hand-written dead code', () {
      expect(symbols, contains('_unusedHandWritten'));
      expect(symbols, contains('_plainDead'));
    });

    test(
        'does not treat a banner phrase below the first declaration as a '
        'generated marker', () {
      expect(symbols, contains('_afterCode'));
    });

    test('does not report complexity or duplication in generated code', () {
      expect(
          findings.where((f) => f.kind == CheckKind.highComplexity), isEmpty);
      expect(findings.where((f) => f.kind == CheckKind.duplicateCode), isEmpty);
    });

    test('leaves generated functions out of the health score', () {
      final health = findings.singleWhere(
        (f) => f.kind == CheckKind.projectHealth,
      );
      final included = analyze(
        fixture,
        checks: {Check.complexity},
        reportGenerated: true,
      );

      expect(
        included.then(
          (all) =>
              all.singleWhere((f) => f.kind == CheckKind.projectHealth).message,
        ),
        completion(isNot(health.message)),
      );
    });
  });

  group('generated code is reported on request', () {
    late List<Finding> findings;
    late Set<String?> symbols;

    setUpAll(() async {
      findings = await analyze(
        fixture,
        checks: Check.values.toSet(),
        reportGenerated: true,
      );
      symbols = findings.map((f) => f.symbol).toSet();
    });

    test('reports dead code in generated files', () {
      expect(symbols, contains(r'_$unusedGenerated'));
      expect(symbols, contains('_bannerDead'));
    });

    test('reports complexity and duplication in generated files', () {
      expect(
        findings.where((f) => f.kind == CheckKind.highComplexity),
        isNotEmpty,
      );
      expect(
        findings.where((f) => f.kind == CheckKind.duplicateCode),
        isNotEmpty,
      );
    });

    test('the config file can ask for the same', () async {
      final viaConfig = await analyze(
        fixture,
        checks: {Check.deadCode},
        config: const DallowConfig(reportGenerated: true),
      );
      expect(viaConfig.map((f) => f.symbol), contains(r'_$unusedGenerated'));
    });
  });

  group('SourceScope', () {
    SourceScope scope(DallowConfig config) =>
        SourceScope(root: fixture, config: config);

    test('recognises generated files by name at any depth', () {
      final defaults = scope(DallowConfig.defaults);

      expect(defaults.isGenerated('lib/src/model.g.dart'), isTrue);
      expect(defaults.isGenerated('lib/a/b/user.freezed.dart'), isTrue);
      expect(defaults.isGenerated('lib/api/service.pb.dart'), isTrue);
      expect(defaults.isGenerated('lib/src/model.dart'), isFalse);
    });

    test('recognises a generated banner in the leading comment', () {
      final defaults = scope(DallowConfig.defaults);

      expect(defaults.isGenerated('lib/src/banner.dart'), isTrue);
      expect(defaults.isGenerated('lib/src/callbacks.dart'), isFalse);
    });

    test('honours extra generated patterns from the config', () {
      final custom = scope(
        const DallowConfig(generatedPatterns: ['lib/src/callbacks.dart']),
      );

      expect(custom.isGenerated('lib/src/callbacks.dart'), isTrue);
    });

    test('a path glob excludes a directory; a name glob matches any depth', () {
      final custom = scope(
        const DallowConfig(exclude: ['lib/legacy/**', '*_old.dart']),
      );

      expect(custom.reports('lib/legacy/deep/file.dart'), isFalse);
      expect(custom.reports('lib/src/thing_old.dart'), isFalse);
      expect(custom.reports('lib/src/thing.dart'), isTrue);
    });

    test('a duplication exclude leaves other checks reporting', () {
      final custom = scope(
        const DallowConfig(duplicationExclude: ['tool/**']),
      );

      expect(custom.scansForDuplication('tool/build.dart'), isFalse);
      expect(custom.reports('tool/build.dart'), isTrue);
    });

    test('test code is left out of duplication only, and by default', () {
      final defaults = scope(DallowConfig.defaults);

      expect(defaults.scansForDuplication('test/a_test.dart'), isFalse);
      expect(
        defaults.scansForDuplication('integration_test/app_test.dart'),
        isFalse,
      );
      expect(defaults.scansForDuplication('test_driver/main.dart'), isFalse);
      expect(defaults.scansForDuplication('lib/test/helper.dart'), isTrue);
      expect(defaults.reports('test/a_test.dart'), isTrue);
    });

    test('duplication scans test code when the config asks for it', () {
      final custom = scope(
        const DallowConfig(duplicationIncludesTests: true),
      );

      expect(custom.scansForDuplication('test/a_test.dart'), isTrue);
    });
  });

  group('declared entrypoints', () {
    test("keeps a symbol annotated @pragma('vm:entry-point')", () async {
      final findings = await analyze(fixture, checks: {Check.deadCode});

      expect(
        findings.map((f) => f.symbol),
        isNot(contains('_backgroundCallback')),
      );
    });
  });
}
