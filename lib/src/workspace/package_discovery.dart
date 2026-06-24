import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

/// How a workspace's member packages were discovered from a root.
enum DiscoveryStrategy {
  /// A `melos.yaml` with `packages:` globs.
  melos,

  /// A pub-workspace root: a `pubspec.yaml` carrying a `workspace:` list.
  pubWorkspace,

  /// Fallback: every nested `pubspec.yaml` found by walking the tree.
  nested,
}

/// The member packages discovered under a root, and how they were found.
class WorkspaceDiscovery {
  const WorkspaceDiscovery(this.strategy, this.packageRoots);

  final DiscoveryStrategy strategy;

  /// Absolute, normalised package-root directories, sorted and de-duplicated.
  /// A directory qualifies as a package root iff it contains a `pubspec.yaml`.
  final List<String> packageRoots;
}

/// Directories that never contain source packages we want to scan. Skipped
/// both when walking for nested packages and when expanding melos globs, so a
/// plugin pubspec copied into `.symlinks/` or a generated package under
/// `.dart_tool/` is not mistaken for a member package.
const _skippedDirs = {
  '.dart_tool',
  '.git',
  '.fvm',
  'build',
  'node_modules',
  '.symlinks',
  '.plugin_symlinks',
};

/// Scans [root] for member packages, choosing a strategy in priority order:
///
/// 1. a `melos.yaml` whose `packages:` globs select the members;
/// 2. a pub-workspace root whose `pubspec.yaml` lists members under
///    `workspace:`;
/// 3. otherwise, every nested `pubspec.yaml` reachable from [root] (including
///    [root] itself when it is a package).
///
/// The walk skips build, tooling and symlink directories so generated or
/// mirrored pubspecs are never treated as members.
WorkspaceDiscovery discoverWorkspace(String root) {
  final normalisedRoot = p.normalize(p.absolute(root));

  final melos = File(p.join(normalisedRoot, 'melos.yaml'));
  if (melos.existsSync()) {
    final config = _melosGlobs(melos.readAsStringSync());
    if (config.packages.isNotEmpty) {
      return WorkspaceDiscovery(
        DiscoveryStrategy.melos,
        _expandGlobs(normalisedRoot, config.packages, config.ignore),
      );
    }
  }

  final rootPubspec = File(p.join(normalisedRoot, 'pubspec.yaml'));
  if (rootPubspec.existsSync()) {
    final members = _workspaceMembers(rootPubspec.readAsStringSync());
    if (members.isNotEmpty) {
      final roots = <String>[];
      for (final relative in members) {
        final dir = p.normalize(p.join(normalisedRoot, relative));
        if (File(p.join(dir, 'pubspec.yaml')).existsSync()) roots.add(dir);
      }
      return WorkspaceDiscovery(
        DiscoveryStrategy.pubWorkspace,
        _sortUnique(roots),
      );
    }
  }

  return WorkspaceDiscovery(
    DiscoveryStrategy.nested,
    _findNestedPackages(normalisedRoot),
  );
}

class _MelosConfig {
  const _MelosConfig(this.packages, this.ignore);
  final List<String> packages;
  final List<String> ignore;
}

_MelosConfig _melosGlobs(String yamlSource) {
  final doc = loadYaml(yamlSource);
  if (doc is! YamlMap) return const _MelosConfig([], []);
  return _MelosConfig(_stringList(doc['packages']), _stringList(doc['ignore']));
}

/// The `workspace:` member paths of a pub-workspace root pubspec, or empty when
/// the field is absent. `pubspec_parse` exposes this as a list of relative
/// paths (not globs).
List<String> _workspaceMembers(String yamlSource) {
  final pubspec = Pubspec.parse(yamlSource);
  return pubspec.workspace ?? const [];
}

List<String> _stringList(Object? node) {
  if (node is! YamlList) return const [];
  return node.whereType<String>().toList();
}

/// Finds every package root matching one of [globs] (and matching none of
/// [ignore]) by walking [root]. Globs are matched against each candidate's
/// path relative to [root], using `/` separators regardless of platform.
List<String> _expandGlobs(
  String root,
  List<String> globs,
  List<String> ignore,
) {
  final include = globs.map(_globToRegExp).toList();
  final exclude = ignore.map(_globToRegExp).toList();
  final matched = <String>[];

  for (final dir in _allPackageDirs(root)) {
    final relative = p.relative(dir, from: root);
    final posix = p.split(relative).join('/');
    final isMember = include.any((re) => re.hasMatch(posix)) &&
        !exclude.any((re) => re.hasMatch(posix));
    if (isMember) matched.add(dir);
  }

  return _sortUnique(matched);
}

/// All package-root directories (containing a `pubspec.yaml`) reachable from
/// [root], excluding [root] itself — melos and pub workspaces enumerate
/// members beneath the root, never the root package.
List<String> _allPackageDirs(String root) {
  final dirs = _findNestedPackages(root);
  return dirs.where((dir) => p.normalize(dir) != p.normalize(root)).toList();
}

/// Walks [root] collecting every directory that contains a `pubspec.yaml`,
/// including [root] itself. Skipped directories ([_skippedDirs]) are not
/// descended into, so mirrored or generated pubspecs are never collected.
List<String> _findNestedPackages(String root) {
  final result = <String>[];
  final start = Directory(root);
  if (!start.existsSync()) return const [];

  final stack = <Directory>[start];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      result.add(p.normalize(dir.path));
    }
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      if (_skippedDirs.contains(p.basename(entity.path))) continue;
      stack.add(entity);
    }
  }
  return _sortUnique(result);
}

List<String> _sortUnique(List<String> paths) {
  final unique = paths.map(p.normalize).toSet().toList()..sort();
  return unique;
}

/// Converts a melos-style glob to an anchored [RegExp]. Supports `*` (any run
/// of characters except `/`), `**` (any characters, including `/`), and `?`
/// (a single non-`/` character) — the subset melos package globs use.
RegExp _globToRegExp(String glob) {
  final buffer = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final char = glob[i];
    if (char == '*') {
      final isDoubleStar = i + 1 < glob.length && glob[i + 1] == '*';
      if (isDoubleStar) {
        i++;
        if (i + 1 < glob.length && glob[i + 1] == '/') {
          // `**/` also matches zero leading segments (`**/example` ~ `example`).
          i++;
          buffer.write('(?:.*/)?');
        } else {
          buffer.write('.*');
        }
      } else {
        buffer.write('[^/]*');
      }
    } else if (char == '?') {
      buffer.write('[^/]');
    } else if (r'\^$.|+()[]{}'.contains(char)) {
      buffer
        ..write(r'\')
        ..write(char);
    } else {
      buffer.write(char);
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString());
}
