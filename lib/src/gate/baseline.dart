import 'dart:convert';

import 'package:dallow/src/finding.dart';
import 'package:dallow/src/gate/finding_filter.dart';
import 'package:dallow/src/gate/fingerprint.dart';

/// One recorded finding in a [Baseline]: its [fingerprint] (the authoritative
/// match key) plus context fields kept purely so the file is human-readable.
class BaselineEntry {
  const BaselineEntry({
    required this.fingerprint,
    this.kind,
    this.file,
    this.symbol,
    this.message,
  });

  final String fingerprint;
  final String? kind;
  final String? file;
  final String? symbol;
  final String? message;

  Map<String, Object?> toJson() => {
        'fingerprint': fingerprint,
        if (kind != null) 'kind': kind,
        if (file != null) 'file': file,
        if (symbol != null) 'symbol': symbol,
        if (message != null) 'message': message,
      };
}

/// A set of known-and-accepted findings, identified by [fingerprintOf], that
/// the PR gate suppresses. Writing a baseline once lets a team adopt the gate
/// on an already-dirty codebase: CI then fails only on findings introduced
/// *after* the baseline was captured.
class Baseline {
  Baseline._(this.entries)
      : fingerprints = {for (final e in entries) e.fingerprint};

  /// Captures the current [findings] as a baseline, de-duplicating findings
  /// that share a fingerprint.
  factory Baseline.fromFindings(Iterable<Finding> findings) {
    final byFingerprint = <String, BaselineEntry>{};
    for (final f in findings) {
      final fingerprint = fingerprintOf(f);
      byFingerprint.putIfAbsent(
        fingerprint,
        () => BaselineEntry(
          fingerprint: fingerprint,
          kind: f.kind.id,
          file: f.file,
          symbol: f.symbol,
          message: f.message,
        ),
      );
    }
    return Baseline._(_sorted(byFingerprint.values));
  }

  /// Parses a baseline document produced by [encode].
  ///
  /// Throws [GateException] if the JSON is malformed or its `version` is not
  /// understood by this build.
  factory Baseline.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw GateException('Baseline file is not valid JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const GateException('Baseline file must be a JSON object.');
    }
    final version = decoded['version'];
    if (version != currentVersion) {
      throw GateException(
        'Unsupported baseline version $version; this dallow writes and reads '
        'version $currentVersion. Re-generate it with --write-baseline.',
      );
    }
    final rawFindings = decoded['findings'];
    if (rawFindings is! List) {
      throw const GateException(
        'Baseline file is missing a "findings" array.',
      );
    }
    final entries = <BaselineEntry>[];
    for (final entry in rawFindings) {
      if (entry is! Map<String, Object?>) {
        throw const GateException(
          'Each baseline entry must be a JSON object.',
        );
      }
      final fingerprint = entry['fingerprint'];
      if (fingerprint is! String) {
        throw const GateException(
          'Each baseline entry must carry a string "fingerprint".',
        );
      }
      entries.add(
        BaselineEntry(
          fingerprint: fingerprint,
          kind: entry['kind'] as String?,
          file: entry['file'] as String?,
          symbol: entry['symbol'] as String?,
          message: entry['message'] as String?,
        ),
      );
    }
    return Baseline._(_sorted(entries));
  }

  /// The current on-disk schema version. Bumped only on a breaking change to
  /// the document shape so an old dallow refuses a newer baseline cleanly.
  static const int currentVersion = 1;

  /// The recorded entries, sorted by fingerprint for a deterministic file.
  final List<BaselineEntry> entries;

  /// The fingerprints of every baselined finding (derived from [entries]).
  final Set<String> fingerprints;

  static List<BaselineEntry> _sorted(Iterable<BaselineEntry> entries) {
    final list = entries.toList()
      ..sort((a, b) => a.fingerprint.compareTo(b.fingerprint));
    return list;
  }

  /// Whether [finding] is already recorded in this baseline.
  bool suppresses(Finding finding) =>
      fingerprints.contains(fingerprintOf(finding));

  /// Drops every baselined finding from [findings], keeping the rest in order.
  List<Finding> apply(List<Finding> findings) =>
      findings.where((f) => !suppresses(f)).toList();

  /// Serialises this baseline to a stable, human-readable JSON document.
  /// Entries are already sorted by fingerprint, so the file is deterministic
  /// and diff-friendly across runs.
  String encode() {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert({
          'version': currentVersion,
          'findings': [for (final e in entries) e.toJson()],
        })}\n';
  }
}

/// Encodes [findings] as a fresh baseline document — the canonical way to
/// write a baseline file (e.g. behind `--write-baseline`).
String encodeBaseline(Iterable<Finding> findings) =>
    Baseline.fromFindings(findings).encode();

/// A [FindingFilter] that suppresses every finding recorded in [baseline].
FindingFilter baselineFilter(Baseline baseline) => baseline.apply;
