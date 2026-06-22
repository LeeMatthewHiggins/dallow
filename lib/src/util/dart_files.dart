import 'dart:io';

import 'package:path/path.dart' as p;

const _skippedDirs = {
  '.dart_tool',
  '.git',
  'build',
  '.fvm',
  'node_modules',
};

/// Lists every `.dart` file belonging to the package at [rootPath].
///
/// Build and tooling directories are skipped, and the walk does not descend
/// into nested packages — any subdirectory carrying its own `pubspec.yaml` is
/// a separate package whose sources belong to it, not to [rootPath].
List<String> listDartFiles(String rootPath) {
  final root = Directory(rootPath);
  if (!root.existsSync()) return const [];

  final files = <String>[];
  final stack = <Directory>[root];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File) {
        if (entity.path.endsWith('.dart')) files.add(entity.path);
        continue;
      }
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if (_skippedDirs.contains(name)) continue;
      if (File(p.join(entity.path, 'pubspec.yaml')).existsSync()) continue;
      stack.add(entity);
    }
  }
  files.sort();
  return files;
}

/// True when [relativePath] sits under the package `lib/` directory.
bool isUnderLib(String relativePath) {
  final segments = p.split(p.normalize(relativePath));
  return segments.isNotEmpty && segments.first == 'lib';
}
