import 'dart:io';

import 'package:dallow/dallow.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('dallowVersion matches the pubspec version', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect(dallowVersion, pubspec['version']);
  });

  test('analyzerVersion matches the resolved analyzer in pubspec.lock',
      () async {
    final lock = loadYaml(File('pubspec.lock').readAsStringSync()) as Map;
    final packages = lock['packages'] as Map;
    final analyzer = packages['analyzer'] as Map;
    expect(await analyzerVersion(), analyzer['version']);
  });

  test('--version prints both versions and exits 0', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'bin/dallow.dart', '--version'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(
      result.stdout as String,
      matches(RegExp(r'^dallow \S+ \(analyzer \d+\.\d+\.\d+')),
    );
  });
}
