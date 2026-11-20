import 'dart:isolate';

/// The dallow release version. `test/version_test.dart` keeps it equal to
/// the `version:` in `pubspec.yaml`.
const dallowVersion = '0.3.0';

/// The `analyzer` version baked in at compile time by `tool/build.sh`
/// (`-DDALLOW_ANALYZER_VERSION=<x.y.z>`). Empty when not set.
const _analyzerVersionDefine = String.fromEnvironment(
  'DALLOW_ANALYZER_VERSION',
);

/// The resolved `analyzer` package version this dallow runs on.
///
/// A compiled binary reports the version `tool/build.sh` baked in. A source
/// run (`dart run`) reads it from the pub-cache path of `package:analyzer`.
/// Returns `unknown` when neither source is available.
Future<String> analyzerVersion() async {
  if (_analyzerVersionDefine.isNotEmpty) return _analyzerVersionDefine;
  // Resolves to null in an AOT binary, which falls through to `unknown`.
  final uri = await Isolate.resolvePackageUri(Uri.parse('package:analyzer/'));
  final match = RegExp(r'analyzer-(\d+\.\d+\.\d+[^/]*)/').firstMatch(
    uri?.path ?? '',
  );
  if (match != null) return match.group(1)!;
  return 'unknown';
}
