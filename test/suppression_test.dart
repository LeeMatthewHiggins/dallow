import 'dart:io';

import 'package:dallow/dallow.dart';
import 'package:dallow/src/checks/duplication_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Finding _finding({
  CheckKind kind = CheckKind.deadCode,
  String file = 'lib/a.dart',
  int? line = 10,
  String symbol = 'foo',
}) =>
    Finding(
      kind: kind,
      severity: Severity.warning,
      message: 'Unused $symbol',
      file: file,
      line: line,
      symbol: symbol,
    );

void main() {
  group('IgnoreDirective.suppresses', () {
    final unscoped = IgnoreDirective(file: 'lib/a.dart', line: 10, kinds: null);

    test('matches a finding on the same line', () {
      expect(unscoped.suppresses(_finding()), isTrue);
    });

    test('matches a finding on the line directly below (comment above)', () {
      expect(unscoped.suppresses(_finding(line: 11)), isTrue);
    });

    test('does not match a finding two lines below or above', () {
      expect(unscoped.suppresses(_finding(line: 12)), isFalse);
      expect(unscoped.suppresses(_finding(line: 9)), isFalse);
    });

    test('does not match a finding in another file', () {
      expect(unscoped.suppresses(_finding(file: 'lib/b.dart')), isFalse);
    });

    test('never matches a whole-package (file-less / line-less) finding', () {
      expect(
        unscoped.suppresses(_finding(line: null)),
        isFalse,
      );
    });

    test('a scoped directive matches only its named kind', () {
      final scoped = IgnoreDirective(
        file: 'lib/a.dart',
        line: 10,
        kinds: {CheckKind.duplicateCode},
      );
      expect(
        scoped.suppresses(_finding(kind: CheckKind.duplicateCode)),
        isTrue,
      );
      expect(scoped.suppresses(_finding()), isFalse);
    });

    test('a scoped directive with an empty kind set matches nothing', () {
      final empty =
          IgnoreDirective(file: 'lib/a.dart', line: 10, kinds: <CheckKind>{});
      expect(empty.suppresses(_finding()), isFalse);
    });
  });

  group('Suppressions.apply', () {
    test('drops suppressed findings and keeps the rest in order', () {
      final suppressions = Suppressions([
        IgnoreDirective(file: 'lib/a.dart', line: 10, kinds: null),
      ]);
      final findings = [
        _finding(symbol: 'kept', line: 5),
        _finding(symbol: 'ignored'),
        _finding(symbol: 'alsoKept', file: 'lib/b.dart'),
      ];
      final survivors = suppressions.apply(findings);
      expect(survivors.map((f) => f.symbol), ['kept', 'alsoKept']);
    });

    test('reports directives that suppressed nothing as unused', () {
      final used = IgnoreDirective(file: 'lib/a.dart', line: 10, kinds: null);
      final stale = IgnoreDirective(file: 'lib/a.dart', line: 99, kinds: null);
      final suppressions = Suppressions([used, stale])..apply([_finding()]);

      expect(suppressions.unused, [stale]);
      final reports = suppressions.unusedFindings;
      expect(reports, hasLength(1));
      expect(reports.single.kind, CheckKind.unusedIgnore);
      expect(reports.single.severity, Severity.info);
      expect(reports.single.line, 99);
    });
  });

  group('composes with the baseline filter (ordering)', () {
    test('suppression-first leaves baseline to gate the remainder', () {
      final suppressions = Suppressions([
        IgnoreDirective(file: 'lib/a.dart', line: 10, kinds: null),
      ]);
      final ignored = _finding(symbol: 'ignored');
      final baselined = _finding(symbol: 'baselined', line: 20);
      final fresh = _finding(symbol: 'fresh', line: 30);

      final baseline = Baseline.fromFindings([baselined]);
      final result = applyFilters(
        [ignored, baselined, fresh],
        [suppressions.apply, baselineFilter(baseline)],
      );

      // The ignored finding is gone via suppression, the baselined one via the
      // baseline, only the genuinely new finding survives to gate.
      expect(result.map((f) => f.symbol), ['fresh']);
    });
  });

  group('SuppressionScanner parses real source comments', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dallow_suppress_');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    File write(String name, String content) =>
        File(p.join(dir.path, name))..writeAsStringSync(content);

    test('captures bare, scoped, same-line and block-comment directives', () {
      write('s.dart', '''
// dallow-ignore
int a = 1;
int b = 2; // dallow-ignore: dead-code
// dallow-ignore: dead-code, duplicate-code
int c = 3;
/* dallow-ignore */
int d = 4;
// just an ordinary comment
int e = 5;
''');
      final directives = const SuppressionScanner().scan(dir.path).directives;
      final byLine = {for (final d in directives) d.line: d};

      expect(byLine[1]!.kinds, isNull); // bare
      expect(byLine[3]!.kinds, {CheckKind.deadCode}); // same-line scoped
      expect(
        byLine[4]!.kinds,
        {CheckKind.deadCode, CheckKind.duplicateCode}, // multi-kind
      );
      expect(byLine[6]!.kinds, isNull); // block comment, bare
      // The ordinary comment on line 8 is not a directive.
      expect(byLine.containsKey(8), isFalse);
      expect(directives, hasLength(4));
    });

    test('ignores look-alikes (dallow-ignored, prose mentions)', () {
      write('s.dart', '''
// dallow-ignored
int a = 1;
// please do not dallow-ignore this
int b = 2;
''');
      final directives = const SuppressionScanner().scan(dir.path).directives;
      expect(directives, isEmpty);
    });

    test('an unrecognised scoped kind yields an empty (no-op) directive', () {
      write('s.dart', '''
// dallow-ignore: not-a-real-kind
int a = 1;
''');
      final directive =
          const SuppressionScanner().scan(dir.path).directives.single;
      expect(directive.kinds, isEmpty);
    });
  });

  group('end-to-end: suppresses a real duplication finding', () {
    late Directory dir;

    // A function body long enough to clear the default duplicate-block size,
    // identical across two files so the duplication check fires.
    const block = '''
() {
  var a = 1;
  var b = 2;
  var c = 3;
  var d = 4;
  var e = 5;
  return a + b + c + d + e;
}
''';

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dallow_dup_suppress_');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    void writePair({required bool withIgnore, String? scopedKind}) {
      final comment = scopedKind == null
          ? '// dallow-ignore'
          : '// dallow-ignore: $scopedKind';
      final header = withIgnore ? '$comment\n' : '';
      // a_dup.dart sorts first, so the finding is anchored to it.
      File(p.join(dir.path, 'a_dup.dart'))
          .writeAsStringSync('${header}int alpha$block');
      File(p.join(dir.path, 'b_dup.dart')).writeAsStringSync('int beta$block');
    }

    List<Finding> dupFindings() => const DuplicationCheck().run(dir.path);

    test('the duplication finding fires without a directive', () {
      writePair(withIgnore: false);
      final findings = dupFindings();
      expect(findings, isNotEmpty);
      expect(findings.first.kind, CheckKind.duplicateCode);
      expect(findings.first.file, 'a_dup.dart');
    });

    test('an unscoped dallow-ignore above the block suppresses it', () {
      writePair(withIgnore: true);
      final findings = dupFindings();
      expect(findings, isNotEmpty, reason: 'check still fires pre-gate');

      final suppressions = const SuppressionScanner().scan(dir.path);
      final gated = suppressions.apply(findings);
      expect(
        gated.where((f) => f.kind == CheckKind.duplicateCode),
        isEmpty,
        reason: 'the dallow-ignore should remove the duplication finding',
      );
    });

    test('a matching scoped directive suppresses; a mismatched one does not',
        () {
      writePair(withIgnore: true, scopedKind: 'duplicate-code');
      var gated =
          const SuppressionScanner().scan(dir.path).apply(dupFindings());
      expect(gated.where((f) => f.kind == CheckKind.duplicateCode), isEmpty);

      writePair(withIgnore: true, scopedKind: 'dead-code');
      gated = const SuppressionScanner().scan(dir.path).apply(dupFindings());
      expect(
        gated.where((f) => f.kind == CheckKind.duplicateCode),
        isNotEmpty,
        reason: 'a dead-code scope must not silence a duplicate-code finding',
      );
    });
  });
}
