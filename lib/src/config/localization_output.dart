import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

abstract final class _GenL10n {
  static const configFile = 'l10n.yaml';
  static const pubspecFile = 'pubspec.yaml';

  static const arbDirKey = 'arb-dir';
  static const outputDirKey = 'output-dir';
  static const outputFileKey = 'output-localization-file';

  static const defaultDir = 'lib/l10n';
  static const defaultFile = 'app_localizations.dart';
  static const dartExtension = '.dart';

  /// The suffix `gen-l10n` gives the class file of one locale: a language
  /// code, optionally followed by script and country codes (`_en`, `_zh_Hant`,
  /// `_pt_BR`).
  static const localeSuffix = '(_[a-z]{2,3}(_[A-Za-z0-9]{2,8})*)?';
}

/// The localisation classes `flutter gen-l10n` writes into a package.
///
/// Those files carry no generated-code banner and no distinctive extension,
/// so they are recognised by where the tool is configured to put them: the
/// `output-dir` (or `arb-dir`) and `output-localization-file` of `l10n.yaml`,
/// or the tool's defaults when the package only sets `flutter: generate: true`
/// in its `pubspec.yaml`.
class LocalizationOutput {
  LocalizationOutput._(this._directory, this._fileName);

  /// Reads the localisation settings of the package at [packageRoot].
  factory LocalizationOutput.forPackage(String packageRoot) {
    final options = _yamlMap(p.join(packageRoot, _GenL10n.configFile));
    if (options == null && !_generatesByDefault(packageRoot)) {
      return LocalizationOutput._(null, null);
    }
    final directory = _string(options, _GenL10n.outputDirKey) ??
        _string(options, _GenL10n.arbDirKey) ??
        _GenL10n.defaultDir;
    final file =
        _string(options, _GenL10n.outputFileKey) ?? _GenL10n.defaultFile;
    return LocalizationOutput._(
      p.posix.normalize(directory),
      RegExp(
        '^${RegExp.escape(p.posix.basenameWithoutExtension(file))}'
        '${_GenL10n.localeSuffix}'
        '${RegExp.escape(_GenL10n.dartExtension)}\$',
      ),
    );
  }

  final String? _directory;
  final RegExp? _fileName;

  /// Whether the file at [relativePath] (relative to the package root, with
  /// `/` separators) is one `gen-l10n` writes.
  bool contains(String relativePath) {
    final fileName = _fileName;
    if (fileName == null) return false;
    return p.posix.dirname(relativePath) == _directory &&
        fileName.hasMatch(p.posix.basename(relativePath));
  }

  static bool _generatesByDefault(String packageRoot) {
    final pubspec = _yamlMap(p.join(packageRoot, _GenL10n.pubspecFile));
    final flutter = pubspec?['flutter'];
    return flutter is YamlMap && flutter['generate'] == true;
  }

  static String? _string(YamlMap? map, String key) {
    final value = map?[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// The YAML map in the file at [path], or null when the file is missing,
  /// unreadable or not a map.
  static YamlMap? _yamlMap(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final document = loadYaml(file.readAsStringSync());
      return document is YamlMap ? document : YamlMap();
    } on Object {
      return null;
    }
  }
}
