import 'dart:io';

import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final configured = p.absolute('test', 'fixtures', 'configured');

  group('DallowConfig.parse', () {
    test('an empty document yields the defaults', () {
      final config = DallowConfig.parse('');

      expect(config.exclude, isEmpty);
      expect(config.reportGenerated, isFalse);
      expect(config.failOn, isNull);
      expect(config.rules, isEmpty);
      expect(config.minBlockSize, isNull);
      expect(config.duplicationIncludesTests, isFalse);
    });

    test('reads every documented key', () {
      final config = DallowConfig.parse('''
exclude:
  - lib/l10n/**
generated:
  report: true
  patterns:
    - "*.gql.dart"
fail-on: warning
rules:
  dead-code: error
  duplicate-code: off
  circular-import: false
dependencies:
  ignore: [build_runner]
circular:
  max-cycle-size: 12
duplication:
  min-block-size: 80
  include-tests: true
  exclude:
    - tool/**
complexity:
  max-complexity: 15
''');

      expect(config.exclude, ['lib/l10n/**']);
      expect(config.reportGenerated, isTrue);
      expect(config.generatedPatterns, ['*.gql.dart']);
      expect(config.failOn, FailOn.warning);
      expect(config.rules, {
        CheckKind.deadCode: RuleLevel.error,
        CheckKind.duplicateCode: RuleLevel.off,
        CheckKind.circularImport: RuleLevel.off,
      });
      expect(config.ignoredDependencies, {'build_runner'});
      expect(config.maxCycleSize, 12);
      expect(config.minBlockSize, 80);
      expect(config.duplicationExclude, ['tool/**']);
      expect(config.duplicationIncludesTests, isTrue);
      expect(config.maxComplexity, 15);
    });

    void rejects(String yaml, String fragment) {
      expect(
        () => DallowConfig.parse(yaml),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.message,
            'message',
            contains(fragment),
          ),
        ),
      );
    }

    test('rejects an unknown top-level key', () {
      rejects('excludes: []', "unknown top-level key 'excludes'");
    });

    test('rejects an unknown nested key', () {
      rejects('duplication:\n  min-tokens: 50', "key 'min-tokens'");
    });

    test('rejects an unknown rule kind', () {
      rejects('rules:\n  dead-cod: off', "key 'dead-cod'");
    });

    test('rejects a rule for unused-ignore, which a flag controls', () {
      rejects('rules:\n  unused-ignore: off', "key 'unused-ignore'");
    });

    test('rejects an unknown rule level', () {
      rejects('rules:\n  dead-code: fatal', 'must be one of');
    });

    test('rejects a threshold below its minimum', () {
      rejects('complexity:\n  max-complexity: 0', 'must be at least 1');
    });

    test('rejects a value of the wrong type', () {
      rejects('exclude: lib/**', 'must be a list of strings');
      rejects('generated:\n  report: maybe', 'must be true or false');
    });

    test('rejects an invalid glob', () {
      rejects('exclude:\n  - "lib/{a"', 'invalid glob');
    });

    test('rejects malformed YAML', () {
      rejects('exclude: [', 'is not valid YAML');
    });
  });

  group('DallowConfig.forPackage', () {
    test('reads the dallow.yaml at the package root', () {
      final config = DallowConfig.forPackage(configured);

      expect(config.maxComplexity, 2);
      expect(config.failOn, FailOn.warning);
    });

    test('falls back to the workspace root, then to the defaults', () {
      final bare = p.absolute('test', 'fixtures', 'generics');

      expect(
        DallowConfig.forPackage(bare, fallbackRoot: configured).maxComplexity,
        2,
      );
      expect(DallowConfig.forPackage(bare).maxComplexity, isNull);
    });
  });

  group('analyze with a dallow.yaml', () {
    late List<Finding> findings;

    setUpAll(() async {
      findings = await analyze(configured, checks: Check.values.toSet());
    });

    test('applies a configured threshold', () {
      final complex = findings.where(
        (f) => f.kind == CheckKind.highComplexity,
      );
      expect(complex.map((f) => f.symbol), contains('decide'));
    });

    test('an explicit argument overrides the configured threshold', () async {
      final relaxed = await analyze(
        configured,
        checks: {Check.complexity},
        maxComplexity: 10,
      );
      expect(relaxed.where((f) => f.kind == CheckKind.highComplexity), isEmpty);
    });

    test('reports a kind at its configured severity', () {
      final dead = findings.singleWhere((f) => f.symbol == '_unused');
      expect(dead.severity, Severity.error);
    });

    test('drops findings located in an excluded path', () {
      expect(findings.map((f) => f.symbol), isNot(contains('_legacyDead')));
    });

    test('never reports an ignored dependency', () {
      expect(
        findings.where((f) => f.kind == CheckKind.unusedDependency),
        isEmpty,
      );
    });

    test('an explicit config replaces the file', () async {
      final plain = await analyze(
        configured,
        checks: {Check.deadCode, Check.dependencies},
        config: DallowConfig.defaults,
      );

      expect(plain.map((f) => f.symbol), contains('_legacyDead'));
      expect(plain.map((f) => f.symbol), contains('meta'));
      expect(
        plain.singleWhere((f) => f.symbol == '_unused').severity,
        Severity.warning,
      );
    });

    test('a rule switched off removes the kind entirely', () async {
      final silenced = await analyze(
        configured,
        checks: Check.values.toSet(),
        config: const DallowConfig(
          rules: {
            CheckKind.deadCode: RuleLevel.off,
            CheckKind.projectHealth: RuleLevel.off,
          },
        ),
      );

      expect(silenced.where((f) => f.kind == CheckKind.deadCode), isEmpty);
      expect(silenced.where((f) => f.kind == CheckKind.projectHealth), isEmpty);
    });
  });

  group('the dallow command', timeout: const Timeout(Duration(minutes: 2)), () {
    Future<ProcessResult> dallow(List<String> args) => Process.run(
          Platform.resolvedExecutable,
          ['run', 'bin/dallow.dart', ...args],
        );

    test('takes fail-on from dallow.yaml, and a flag overrides it', () async {
      final configuredRun = await dallow(['complexity', configured]);
      expect(configuredRun.exitCode, 1, reason: '${configuredRun.stderr}');

      final overridden = await dallow(
        ['complexity', configured, '--fail-on', 'never'],
      );
      expect(overridden.exitCode, 0, reason: '${overridden.stderr}');
    });

    test('exits 64 naming the problem in an invalid config', () async {
      final dir = Directory.systemTemp.createTempSync('dallow_config_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = File(p.join(dir.path, 'bad.yaml'))
        ..writeAsStringSync('excludes: []');

      final result = await dallow(['deps', configured, '--config', bad.path]);

      expect(result.exitCode, 64);
      expect(result.stderr, contains("unknown top-level key 'excludes'"));
    });

    test('exits 64 when --config names a missing file', () async {
      final result = await dallow(
        ['deps', configured, '--config', 'no-such-dallow.yaml'],
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Could not read config file'));
    });
  });
}
