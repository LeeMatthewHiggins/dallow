import 'dart:convert';

import 'package:dallow/dallow.dart';
import 'package:test/test.dart';

/// Schema-shape tests for the SARIF 2.1.0 reporter. They parse the emitted
/// string back through [jsonDecode] and assert the structural contract a
/// code-scanning platform relies on, rather than matching exact bytes.
void main() {
  // Typed navigation helpers over decoded JSON — `jsonDecode` yields `Object?`,
  // so these centralise the casts and keep each assertion readable.
  Map<String, Object?> obj(Object? value) => value! as Map<String, Object?>;
  List<Object?> arr(Object? value) => value! as List<Object?>;

  Map<String, Object?> decode(List<Finding> findings) =>
      obj(jsonDecode(Reporter(ReportFormat.sarif).render(findings)));

  Map<String, Object?> theRun(List<Finding> findings) =>
      obj(arr(decode(findings)['runs']).single);

  Map<String, Object?> theDriver(List<Finding> findings) =>
      obj(obj(theRun(findings)['tool'])['driver']);

  List<Object?> theResults(List<Finding> findings) =>
      arr(theRun(findings)['results']);

  // A finding tied to a concrete source line.
  const located = Finding(
    kind: CheckKind.deadCode,
    severity: Severity.warning,
    message: 'Unused top-level function `helper`.',
    file: 'lib/src/foo.dart',
    line: 12,
    symbol: 'helper',
  );

  // A whole-package / file-less finding (no physicalLocation).
  const fileless = Finding(
    kind: CheckKind.circularImport,
    severity: Severity.warning,
    message: 'Import cycle spanning 3 files.',
  );

  // An error-severity finding, to exercise the level mapping. It is also a
  // `pubspec.yaml`-level finding (a file but no line), exercising the
  // file-without-line location contract.
  const errorLevel = Finding(
    kind: CheckKind.missingDependency,
    severity: Severity.error,
    message: 'Package `meta` is imported but not in pubspec.yaml.',
    file: 'pubspec.yaml',
  );

  group('SARIF log envelope', () {
    test('declares version 2.1.0 and the 2.1.0 schema URL', () {
      final log = decode([located]);
      expect(log['version'], '2.1.0');
      expect(log[r'$schema'], isA<String>());
      expect(log[r'$schema']! as String, contains('2.1.0'));
    });

    test('emits exactly one run', () {
      expect(arr(decode([located])['runs']), hasLength(1));
    });

    test('round-trips through jsonDecode even with no findings', () {
      expect(theResults(const []), isEmpty);
    });
  });

  group('tool.driver', () {
    test('names dallow and carries an informationUri', () {
      final driver = theDriver([located]);
      expect(driver['name'], 'dallow');
      expect(driver['informationUri'], isA<String>());
      expect(driver['informationUri']! as String, startsWith('http'));
    });

    test(
        'every CheckKind yields a rule with a non-null shortDescription.text '
        'and defaultConfiguration.level', () {
      // Regression: the rule catalogue is built by looking each CheckKind up in
      // the description/severity maps with a null-assert. A kind missing from
      // either map (e.g. a check added by a later feature) makes `render` throw
      // on every run. Asserting the contract per kind catches that the moment a
      // new CheckKind is introduced without a catalogue entry.
      final rules = arr(theDriver([located])['rules']);
      final byId = {
        for (final raw in rules) obj(raw)['id']! as String: obj(raw),
      };
      const levels = {'error', 'warning', 'note'};
      for (final kind in CheckKind.values) {
        final rule = byId[kind.id];
        expect(rule, isNotNull, reason: 'no rule emitted for ${kind.id}');
        final text = obj(rule!['shortDescription'])['text'];
        expect(text, isA<String>(), reason: '${kind.id} shortDescription.text');
        expect((text! as String).trim(), isNotEmpty,
            reason: '${kind.id} shortDescription.text is blank');
        final level = obj(rule['defaultConfiguration'])['level'];
        expect(levels, contains(level),
            reason: '${kind.id} defaultConfiguration.level');
      }
    });

    test('declares one rule per CheckKind with id, name and a level', () {
      final rules = arr(theDriver([located])['rules']);
      expect(rules, hasLength(CheckKind.values.length));

      final ids = <String>{};
      const levels = {'error', 'warning', 'note'};
      for (final raw in rules) {
        final rule = obj(raw);
        expect(rule['id'], isA<String>());
        expect(rule['name'], isA<String>());
        expect(obj(rule['shortDescription'])['text'], isA<String>());
        expect(levels, contains(obj(rule['defaultConfiguration'])['level']));
        ids.add(rule['id']! as String);
      }
      // One rule per CheckKind => ids cover every kind id, no duplicates.
      expect(ids, CheckKind.values.map((k) => k.id).toSet());
    });
  });

  group('results', () {
    test('a located finding carries ruleId, level, message and a region', () {
      final result = obj(theResults([located]).single);
      expect(result['ruleId'], CheckKind.deadCode.id);
      expect(result['level'], 'warning');
      expect(obj(result['message'])['text'], located.message);

      final location = obj(arr(result['locations']).single);
      final physical = obj(location['physicalLocation']);
      expect(obj(physical['artifactLocation'])['uri'], 'lib/src/foo.dart');
      expect(obj(physical['region'])['startLine'], 12);
    });

    test('a file-less finding still produces a valid result without locations',
        () {
      final result = obj(theResults([fileless]).single);
      expect(result['ruleId'], CheckKind.circularImport.id);
      expect(result['level'], 'warning');
      expect(obj(result['message'])['text'], fileless.message);
      // No physicalLocation: a result with no locations is still valid SARIF.
      expect(result.containsKey('locations'), isFalse);
    });

    test('error severity maps to the SARIF error level', () {
      expect(obj(theResults([errorLevel]).single)['level'], 'error');
    });

    test('a pubspec.yaml-level finding (file but no line) carries no locations',
        () {
      // GitHub code scanning needs `region.startLine` to place an annotation;
      // a `physicalLocation` with a file but no region pins to line 1. So a
      // finding with a file but no line must emit no `locations` at all, with
      // the file it concerns preserved in the message text instead.
      final result = obj(theResults([errorLevel]).single);
      expect(result['ruleId'], CheckKind.missingDependency.id);
      expect(result.containsKey('locations'), isFalse);
      expect(obj(result['message'])['text'], contains('pubspec.yaml'));
    });

    test('every result ruleId matches a declared rule id', () {
      final findings = [located, fileless, errorLevel];
      final ruleIds = {
        for (final r in arr(theDriver(findings)['rules']))
          obj(r)['id']! as String,
      };
      final results = theResults(findings);
      for (final raw in results) {
        expect(ruleIds, contains(obj(raw)['ruleId']));
      }
      expect(results, hasLength(3));
    });
  });
}
