import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/util/dart_files.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';

/// Packages that are legitimately depended on without ever appearing in an
/// `import`/`export` directive (build tooling, lint rule sets, asset-only
/// plugins resolved by the Flutter toolchain).
const _toolingPackages = {
  'flutter',
  'sky_engine',
  'build_runner',
  'build_config',
  'very_good_analysis',
  'lints',
  'flutter_lints',
  'cupertino_icons',
};

/// Federated-plugin suffixes. A platform implementation (`<base>_web`,
/// `<base>_android`, …) or the shared interface (`<base>_platform_interface`)
/// is pulled in so the right code is bundled per platform, but is never
/// imported directly — the app imports `<base>` only. Such a dependency is
/// not "unused" when its base plugin is also a declared dependency.
const _federatedSuffixes = [
  '_platform_interface',
  '_android',
  '_ios',
  '_web',
  '_macos',
  '_windows',
  '_linux',
];

/// Captures the package name of a `package:` URI.
final _packageUri = RegExp('^package:([a-zA-Z0-9_]+)/');

/// Cross-references declared `pubspec.yaml` dependencies against the
/// `package:` imports actually present in the source tree.
class DependencyCheck {
  const DependencyCheck();

  /// Cross-checks `pubspec.yaml` against the imports under [rootPath]. A
  /// package named in [ignored] is never reported.
  List<Finding> run(String rootPath, {Set<String> ignored = const {}}) {
    final pubspecFile = File(p.join(rootPath, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) return const [];

    final pubspec = Pubspec.parse(pubspecFile.readAsStringSync());
    final selfName = pubspec.name;
    final dependencies = pubspec.dependencies.keys.toSet();
    final devDependencies = pubspec.devDependencies.keys.toSet();

    final usedAnywhere = <String>{};
    final usedUnderLib = <String>{};
    for (final path in listDartFiles(rootPath)) {
      final relative = p.relative(path, from: rootPath);
      final underLib = isUnderLib(relative);
      for (final name in _importedPackages(path)) {
        usedAnywhere.add(name);
        if (underLib) usedUnderLib.add(name);
      }
    }

    final findings = <Finding>[
      ..._unusedDependencies(dependencies, usedAnywhere),
      ..._misplacedDependencies(devDependencies, usedUnderLib),
      ..._missingDependencies(
        usedAnywhere,
        selfName,
        dependencies,
        devDependencies,
      ),
    ];

    return findings
      ..removeWhere((f) => ignored.contains(f.symbol))
      ..sort((a, b) => (a.symbol ?? '').compareTo(b.symbol ?? ''));
  }

  /// The packages the file at [path] imports or exports.
  ///
  /// Read from the parsed directives, so a `package:` URI inside a comment or
  /// a string literal — source text held in a test, say — is not mistaken for
  /// a real import. The alternatives of a conditional import are not counted.
  Iterable<String> _importedPackages(String path) sync* {
    final unit = parseDartFile(path).unit;
    for (final directive in unit.directives.whereType<NamespaceDirective>()) {
      final uri = directive.uri.stringValue;
      final match = uri == null ? null : _packageUri.firstMatch(uri);
      if (match != null) yield match.group(1)!;
    }
  }

  Iterable<Finding> _unusedDependencies(
    Set<String> dependencies,
    Set<String> usedAnywhere,
  ) sync* {
    for (final name in dependencies) {
      if (usedAnywhere.contains(name) ||
          _toolingPackages.contains(name) ||
          _isFederatedImplementation(name, dependencies)) {
        continue;
      }
      yield Finding(
        kind: CheckKind.unusedDependency,
        severity: Severity.warning,
        message: "Dependency '$name' is declared but never imported.",
        file: 'pubspec.yaml',
        symbol: name,
      );
    }
  }

  bool _isFederatedImplementation(String name, Set<String> dependencies) {
    for (final suffix in _federatedSuffixes) {
      if (!name.endsWith(suffix)) continue;
      final base = name.substring(0, name.length - suffix.length);
      if (base.isNotEmpty && dependencies.contains(base)) return true;
    }
    return false;
  }

  Iterable<Finding> _misplacedDependencies(
    Set<String> devDependencies,
    Set<String> usedUnderLib,
  ) sync* {
    for (final name in devDependencies) {
      if (!usedUnderLib.contains(name)) continue;
      yield Finding(
        kind: CheckKind.misplacedDependency,
        severity: Severity.warning,
        message: "Dev dependency '$name' is imported from lib/ and should be "
            'a regular dependency.',
        file: 'pubspec.yaml',
        symbol: name,
      );
    }
  }

  Iterable<Finding> _missingDependencies(
    Set<String> usedAnywhere,
    String selfName,
    Set<String> dependencies,
    Set<String> devDependencies,
  ) sync* {
    for (final name in usedAnywhere) {
      if (name == selfName) continue;
      if (dependencies.contains(name) || devDependencies.contains(name)) {
        continue;
      }
      yield Finding(
        kind: CheckKind.missingDependency,
        severity: Severity.error,
        message: "Package '$name' is imported but not declared in "
            'pubspec.yaml.',
        file: 'pubspec.yaml',
        symbol: name,
      );
    }
  }
}
