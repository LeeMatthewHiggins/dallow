import 'dart:convert';
import 'dart:io';

import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Finding _dead({
  String file = 'lib/a.dart',
  String symbol = 'foo',
  int? line,
  String message = 'Unused function foo',
}) =>
    Finding(
      kind: CheckKind.deadCode,
      severity: Severity.warning,
      message: message,
      file: file,
      line: line,
      symbol: symbol,
    );

void main() {
  group('fingerprint', () {
    test('is stable when only the line moves', () {
      // A finding that shifts down the file (line 3 -> 30) keeps its identity:
      // the fingerprint is derived from kind+file+symbol+message, never line.
      expect(
        fingerprintOf(_dead(line: 3)),
        fingerprintOf(_dead(line: 30)),
      );
    });

    test('is stable across insignificant message whitespace', () {
      expect(
        fingerprintOf(_dead()),
        fingerprintOf(_dead(message: '  Unused   function\n foo  ')),
      );
    });

    test('differs when the symbol differs', () {
      expect(
        fingerprintOf(_dead()),
        isNot(fingerprintOf(_dead(symbol: 'bar'))),
      );
    });

    test('differs when the file differs', () {
      expect(
        fingerprintOf(_dead()),
        isNot(fingerprintOf(_dead(file: 'lib/b.dart'))),
      );
    });

    test('differs when the kind differs', () {
      final a = _dead();
      final b = Finding(
        kind: CheckKind.unusedDependency,
        severity: a.severity,
        message: a.message,
        file: a.file,
        symbol: a.symbol,
      );
      expect(fingerprintOf(a), isNot(fingerprintOf(b)));
    });
  });

  group('baseline', () {
    test('round-trips through JSON and suppresses every baselined finding', () {
      final findings = [
        _dead(),
        _dead(symbol: 'bar', file: 'lib/b.dart'),
      ];
      final baseline = Baseline.fromFindings(findings);

      final reparsed = Baseline.parse(baseline.encode());

      expect(reparsed.apply(findings), isEmpty);
      for (final f in findings) {
        expect(reparsed.suppresses(f), isTrue);
      }
    });

    test('lets a newly-introduced finding through after a line shift', () {
      final original = [_dead(line: 3)];
      final baseline = Baseline.fromFindings(original);

      // Same finding, moved down the file, plus a brand-new one.
      final next = [
        _dead(line: 99),
        _dead(symbol: 'brandNew', line: 12),
      ];

      final survivors = baseline.apply(next);
      expect(survivors.map((f) => f.symbol), ['brandNew']);
    });

    test('encodes a versioned, human-readable JSON document', () {
      final baseline = Baseline.fromFindings([_dead()]);
      final decoded = jsonDecode(baseline.encode())! as Map<String, Object?>;

      expect(decoded['version'], 1);
      final entries = decoded['findings']! as List<Object?>;
      expect(entries, hasLength(1));
      final entry = entries.single! as Map<String, Object?>;
      expect(entry['fingerprint'], isA<String>());
      // Context fields are carried for debuggability.
      expect(entry['kind'], 'dead-code');
      expect(entry['symbol'], 'foo');
    });

    test('parse rejects a baseline of an unknown version', () {
      final bad = jsonEncode({'version': 999, 'findings': <Object?>[]});
      expect(() => Baseline.parse(bad), throwsA(isA<GateException>()));
    });
  });

  group('changed-since git diff', () {
    late Directory repo;

    Future<void> git(List<String> args) async {
      final r = await Process.run('git', ['-C', repo.path, ...args]);
      if (r.exitCode != 0) {
        throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
      }
    }

    setUp(() async {
      repo = Directory.systemTemp.createTempSync('dallow_gate_');
      await git(['init', '-q', '-b', 'main']);
      await git(['config', 'user.email', 'test@example.com']);
      await git(['config', 'user.name', 'Test']);
      await git(['config', 'commit.gpgsign', 'false']);
      File(p.join(repo.path, 'a.dart')).writeAsStringSync('// a\n');
      File(p.join(repo.path, 'b.dart')).writeAsStringSync('// b\n');
      await git(['add', '.']);
      await git(['commit', '-q', '-m', 'initial']);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('returns only files changed since the ref (merge-base form)',
        () async {
      // Branch off, change a.dart only, commit.
      await git(['checkout', '-q', '-b', 'feature']);
      File(p.join(repo.path, 'a.dart')).writeAsStringSync('// a changed\n');
      await git(['commit', '-aqm', 'touch a']);

      final changed =
          await changedFilesSince('main', packageRoot: repo.path);
      expect(changed, contains('a.dart'));
      expect(changed, isNot(contains('b.dart')));
    });

    test('resolves files relative to the package root in a sub-package',
        () async {
      // pkg/ is a sub-directory; its findings use pkg-relative paths.
      final pkg = Directory(p.join(repo.path, 'pkg'))..createSync();
      File(p.join(pkg.path, 'lib.dart')).writeAsStringSync('// x\n');
      await git(['add', '.']);
      await git(['commit', '-qm', 'add pkg']);
      final base = (await Process.run(
        'git',
        ['-C', repo.path, 'rev-parse', 'HEAD'],
      ))
          .stdout
          .toString()
          .trim();

      File(p.join(pkg.path, 'lib.dart')).writeAsStringSync('// x changed\n');
      await git(['commit', '-aqm', 'touch pkg/lib']);

      final changed = await changedFilesSince(base, packageRoot: pkg.path);
      // Reported relative to pkg/, not the repo root.
      expect(changed, contains('lib.dart'));
      expect(changed, isNot(contains('pkg/lib.dart')));
    });

    test('throws GateException on a bad ref', () async {
      expect(
        () => changedFilesSince('no-such-ref', packageRoot: repo.path),
        throwsA(isA<GateException>()),
      );
    });

    test('throws GateException outside a git repository', () async {
      final notRepo = Directory.systemTemp.createTempSync('dallow_norepo_');
      addTearDown(() => notRepo.deleteSync(recursive: true));
      expect(
        () => changedFilesSince('HEAD', packageRoot: notRepo.path),
        throwsA(isA<GateException>()),
      );
    });
  });

  group('changed-since filter', () {
    final findings = [
      _dead(symbol: 'inChanged'),
      _dead(file: 'lib/b.dart', symbol: 'inUnchanged'),
      const Finding(
        kind: CheckKind.unusedDependency,
        severity: Severity.warning,
        message: 'meta is unused',
        file: 'pubspec.yaml',
        symbol: 'meta',
      ),
      const Finding(
        kind: CheckKind.missingDependency,
        severity: Severity.error,
        message: 'whole-package signal',
        symbol: 'collection',
      ),
    ];

    test('keeps findings in changed files and drops the rest', () {
      final kept = changedSinceFilter({'lib/a.dart'})(findings);
      expect(kept.map((f) => f.symbol), contains('inChanged'));
      expect(kept.map((f) => f.symbol), isNot(contains('inUnchanged')));
    });

    test('always keeps whole-package findings (file-less or pubspec)', () {
      // Nothing changed, yet dependency-level findings survive.
      final kept = changedSinceFilter(<String>{})(findings);
      expect(kept.map((f) => f.symbol), containsAll(['meta', 'collection']));
      expect(kept.map((f) => f.symbol), isNot(contains('inChanged')));
    });
  });

  group('filter pipeline', () {
    test('composes filters in order', () {
      final findings = [
        _dead(symbol: 'a'),
        _dead(symbol: 'b'),
        _dead(symbol: 'c'),
      ];
      List<Finding> dropFirst(List<Finding> fs) => fs.skip(1).toList();
      List<Finding> dropLast(List<Finding> fs) =>
          fs.take(fs.length - 1).toList();

      final result = applyFilters(findings, [dropFirst, dropLast]);
      expect(result.map((f) => f.symbol), ['b']);
    });
  });
}
