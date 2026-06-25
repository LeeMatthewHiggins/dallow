import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Package roots discovered under [root], expressed as `/`-separated paths
/// relative to [root], so assertions don't depend on the absolute checkout
/// location.
List<String> _relativeRoots(WorkspaceDiscovery discovery, String root) =>
    discovery.packageRoots
        .map((dir) => p.split(p.relative(dir, from: root)).join('/'))
        .toList();

void main() {
  final fixtures = p.absolute('test', 'fixtures');

  group('melos discovery', () {
    final root = p.join(fixtures, 'melos_repo');
    late WorkspaceDiscovery discovery;

    setUpAll(() => discovery = discoverWorkspace(root));

    test('selects packages by the melos `packages:` globs', () {
      expect(discovery.strategy, DiscoveryStrategy.melos);
      expect(
        _relativeRoots(discovery, root),
        containsAll(<String>['packages/alpha', 'packages/beta']),
      );
    });

    test('honours the melos `ignore:` list', () {
      expect(
          _relativeRoots(discovery, root), isNot(contains('packages/ignored')));
    });

    test('never collects pubspecs under skipped dirs (.symlinks)', () {
      expect(
        discovery.packageRoots.any((d) => d.contains('.symlinks')),
        isFalse,
      );
    });

    test('excludes the workspace root itself', () {
      expect(_relativeRoots(discovery, root), isNot(contains('.')));
    });
  });

  group('melos glob subset', () {
    final root = p.join(fixtures, 'brace_repo');
    late WorkspaceDiscovery discovery;

    setUpAll(() => discovery = discoverWorkspace(root));

    test('expands {a,b} brace alternation across both branches', () {
      // The exact failure this PR exists to fix: `{examples,e2e}/**` must
      // select both trees, not be treated as a literal that matches nothing.
      expect(
        _relativeRoots(discovery, root),
        containsAll(<String>['examples/demo', 'e2e/smoke']),
      );
    });

    test('matches plain ** alongside a brace glob (mixed config)', () {
      expect(_relativeRoots(discovery, root), contains('packages/core'));
    });

    test('matches **/ zero-leading-segment with a ? wildcard', () {
      // `**/single?` matches a top-level `singleX` (zero leading segments,
      // single trailing char) — the previously-untested matcher branches.
      expect(_relativeRoots(discovery, root), contains('singleX'));
    });

    test('excludes a package matched by no include glob', () {
      expect(_relativeRoots(discovery, root), isNot(contains('other/thing')));
    });
  });

  group('unsupported glob handling', () {
    final root = p.join(fixtures, 'unsupported_glob_repo');

    test('rejects an unsupported glob loudly instead of matching nothing', () {
      // A character class can't be faithfully translated; refusing it (rather
      // than silently dropping the package) keeps a misread glob from yielding
      // a falsely-clean report.
      expect(
        () => discoverWorkspace(root),
        throwsA(isA<UnsupportedGlobException>()),
      );
    });
  });

  group('pub-workspace discovery', () {
    final root = p.join(fixtures, 'pub_workspace_repo');
    late WorkspaceDiscovery discovery;

    setUpAll(() => discovery = discoverWorkspace(root));

    test('uses the `workspace:` member list', () {
      expect(discovery.strategy, DiscoveryStrategy.pubWorkspace);
      expect(
        _relativeRoots(discovery, root),
        unorderedEquals(<String>['pkgs/one', 'pkgs/two']),
      );
    });

    test('ignores packages not listed under `workspace:`', () {
      expect(_relativeRoots(discovery, root), isNot(contains('pkgs/three')));
    });
  });

  group('nested-pubspec fallback discovery', () {
    final root = p.join(fixtures, 'nested_repo');
    late WorkspaceDiscovery discovery;

    setUpAll(() => discovery = discoverWorkspace(root));

    test('falls back to every nested pubspec, including the root', () {
      expect(discovery.strategy, DiscoveryStrategy.nested);
      expect(
        _relativeRoots(discovery, root),
        unorderedEquals(<String>['.', 'app', 'tools/gen']),
      );
    });
  });

  group('workspace aggregation', () {
    final root = p.join(fixtures, 'melos_repo');
    late List<Finding> findings;

    setUpAll(() async => findings = await analyzeWorkspace(root));

    Iterable<Finding> forPackage(String package) =>
        findings.where((f) => f.package == package);

    test('attributes every finding to its member package', () {
      expect(findings, isNotEmpty);
      expect(findings.every((f) => f.package != null), isTrue);
      expect(
        findings.map((f) => f.package).toSet(),
        containsAll(<String>['packages/alpha', 'packages/beta']),
      );
    });

    test("surfaces alpha's dead-code finding, attributed to alpha", () {
      final deadCode = forPackage('packages/alpha')
          .where((f) => f.kind == CheckKind.deadCode);
      expect(deadCode.map((f) => f.symbol), contains('deadAlphaSymbol'));
    });

    test("surfaces beta's missing-dependency error, attributed to beta", () {
      final missing = forPackage('packages/beta')
          .where((f) => f.kind == CheckKind.missingDependency);
      expect(missing.map((f) => f.symbol), contains('collection'));
    });

    test('JSON output carries the package field', () {
      final json = Reporter(ReportFormat.json).render(findings);
      expect(json, contains('"package": "packages/alpha"'));
      expect(json, contains('"package": "packages/beta"'));
    });
  });

  group('workspace exit-code gating across packages', () {
    final root = p.join(fixtures, 'melos_repo');
    late List<Finding> findings;

    setUpAll(() async => findings = await analyzeWorkspace(root));

    test('fail-on error gates on an error found in any package', () {
      // The error lives in beta; the aggregated list still gates.
      expect(exitCodeFor(findings, failOn: FailOn.error), 1);
    });

    test('fail-on never passes even with cross-package findings', () {
      expect(exitCodeFor(findings, failOn: FailOn.never), 0);
    });

    test('error and warning come from different packages', () {
      final errorPackages = findings
          .where((f) => f.severity == Severity.error)
          .map((f) => f.package)
          .toSet();
      final warningPackages = findings
          .where((f) => f.severity == Severity.warning)
          .map((f) => f.package)
          .toSet();
      expect(errorPackages, contains('packages/beta'));
      expect(warningPackages, contains('packages/alpha'));
    });
  });

  group('reporter renders the package attribution', () {
    final finding = const Finding(
      kind: CheckKind.deadCode,
      severity: Severity.warning,
      message: 'never used',
      file: 'lib/orphan.dart',
      line: 7,
      symbol: 'orphan',
    ).withPackage('pkg/x');

    test('console output prefixes the location with the package path', () {
      final out = Reporter(ReportFormat.console).render([finding]);
      expect(out, contains('pkg/x: lib/orphan.dart:7'));
    });

    test('console output keeps the package prefix when there is no file', () {
      final fileless = const Finding(
        kind: CheckKind.deadCode,
        severity: Severity.warning,
        message: 'package-level note',
      ).withPackage('pkg/x');
      final out = Reporter(ReportFormat.console).render([fileless]);
      expect(out, contains('pkg/x: package-level note'));
    });

    test('markdown output carries the package in the location column', () {
      final out = Reporter(ReportFormat.markdown).render([finding]);
      expect(out, contains('`pkg/x` `lib/orphan.dart:7`'));
    });

    test('single-package output omits the package prefix (unchanged)', () {
      const bare = Finding(
        kind: CheckKind.deadCode,
        severity: Severity.warning,
        message: 'never used',
        file: 'lib/orphan.dart',
        line: 7,
      );
      // The file follows the check id directly — no `<package>: ` in between.
      expect(
        Reporter(ReportFormat.console).render([bare]),
        contains('[dead-code] lib/orphan.dart:7'),
      );
    });
  });
}
