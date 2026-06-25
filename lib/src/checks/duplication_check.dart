import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/util/dart_files.dart';
import 'package:path/path.dart' as p;

/// The smallest duplicate token block worth reporting.
const minDuplicateBlockSize = 4;

/// Default token block size for duplicate code detection.
const defaultDuplicateBlockSize = 20;

/// Detects repeated lexical token sequences across Dart source files.
///
/// The check intentionally stays lexical: identifiers and literals are
/// normalised so structurally identical blocks match, while keywords and
/// punctuation remain exact to keep matches conservative.
class DuplicationCheck {
  const DuplicationCheck();

  List<Finding> run(String rootPath, {int? minBlockSize}) {
    final blockSize = minBlockSize ?? defaultDuplicateBlockSize;
    final sourceRoot = _sourceRoot(rootPath);
    final tokens = <_LexToken>[];

    for (final path in _dartFiles(rootPath)) {
      final relativePath = p.relative(path, from: sourceRoot);
      tokens
        ..addAll(_scanFile(path, relativePath))
        ..add(_LexToken(_sentinel(path), relativePath, -1, -1));
    }

    if (tokens.length < blockSize * 2) return const [];

    final suffixes = List<int>.generate(tokens.length, (index) => index)
      ..sort((a, b) => _compareSuffixes(tokens, a, b));

    final candidates = <_Candidate>[];
    for (var i = 1; i < suffixes.length; i++) {
      final first = suffixes[i - 1];
      final second = suffixes[i];
      final length = _commonPrefix(tokens, first, second);
      if (length >= blockSize) {
        candidates.add(_Candidate(first, second, length));
      }
    }

    candidates.sort((a, b) => b.length.compareTo(a.length));

    final findings = <Finding>[];
    final accepted = <_Range>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      if (_isCovered(candidate, accepted)) continue;

      final key = _sequenceKey(tokens, candidate.start, candidate.length);
      if (!seen.add(key)) continue;

      final occurrences = _occurrences(tokens, suffixes, candidate);
      if (occurrences.length < 2) continue;

      accepted.addAll(
        occurrences.map((o) => _Range(o.index, o.index + candidate.length)),
      );
      findings.add(_findingFor(occurrences, candidate.length));
    }

    findings.sort((a, b) {
      final fileOrder = (a.file ?? '').compareTo(b.file ?? '');
      if (fileOrder != 0) return fileOrder;
      return (a.line ?? 0).compareTo(b.line ?? 0);
    });
    return findings;
  }

  Finding _findingFor(List<_Occurrence> occurrences, int length) {
    final first = occurrences.first;
    final locations = occurrences
        .map((o) => '${o.file}:${o.line}')
        .toList(growable: false)
        .join(', ');
    return Finding(
      kind: CheckKind.duplicateCode,
      severity: Severity.warning,
      message: 'Duplicated code block ($length tokens) at $locations.',
      file: first.file,
      line: first.line,
    );
  }

  List<_Occurrence> _occurrences(
    List<_LexToken> tokens,
    List<int> suffixes,
    _Candidate candidate,
  ) {
    final sequence = _sequence(tokens, candidate.start, candidate.length);
    final occurrences = <_Occurrence>[];

    for (final suffix in suffixes) {
      if (!_matches(tokens, suffix, sequence)) continue;
      final token = tokens[suffix];
      final occurrence = _Occurrence(suffix, token.file, token.line);
      if (_overlapsKept(occurrence, occurrences, candidate.length)) continue;
      occurrences.add(occurrence);
    }

    occurrences.sort((a, b) {
      final fileOrder = a.file.compareTo(b.file);
      if (fileOrder != 0) return fileOrder;
      return a.line.compareTo(b.line);
    });
    return occurrences;
  }

  bool _overlapsKept(
    _Occurrence occurrence,
    List<_Occurrence> kept,
    int length,
  ) {
    for (final other in kept) {
      if (other.file != occurrence.file) continue;
      final startsBeforeOtherEnds = occurrence.index < other.index + length;
      final otherStartsBeforeEnd = other.index < occurrence.index + length;
      if (startsBeforeOtherEnds && otherStartsBeforeEnd) return true;
    }
    return false;
  }

  List<String> _dartFiles(String rootPath) {
    final file = File(rootPath);
    if (file.existsSync() && rootPath.endsWith('.dart')) return [file.path];
    return listDartFiles(rootPath);
  }

  String _sourceRoot(String rootPath) {
    final file = File(rootPath);
    if (file.existsSync() && rootPath.endsWith('.dart')) {
      return p.dirname(file.path);
    }
    return rootPath;
  }

  List<_LexToken> _scanFile(String path, String relativePath) {
    final content = File(path).readAsStringSync();
    final parsed = parseString(
      content: content,
      featureSet: FeatureSet.latestLanguageVersion(),
      path: path,
      throwIfDiagnostics: false,
    );

    final result = <_LexToken>[];
    Token? token = parsed.unit.beginToken;
    while (token != null && !token.isEof) {
      result.add(
        _LexToken(
          _normalise(token),
          relativePath,
          parsed.lineInfo.getLocation(token.offset).lineNumber,
          token.offset,
        ),
      );
      token = token.next;
    }
    return result;
  }

  String _normalise(Token token) {
    if (token.isIdentifier) return '<identifier>';
    final type = token.type;
    if (type == TokenType.INT ||
        type == TokenType.INT_WITH_SEPARATORS ||
        type == TokenType.DOUBLE ||
        type == TokenType.DOUBLE_WITH_SEPARATORS ||
        type == TokenType.HEXADECIMAL ||
        type == TokenType.HEXADECIMAL_WITH_SEPARATORS) {
      return '<number>';
    }
    if (type == TokenType.STRING ||
        type == TokenType.STRING_INTERPOLATION_EXPRESSION ||
        type == TokenType.STRING_INTERPOLATION_IDENTIFIER) {
      return '<string>';
    }
    return token.lexeme;
  }

  String _sentinel(String path) => '<file:${p.normalize(path)}>';

  bool _isCovered(_Candidate candidate, List<_Range> accepted) {
    for (final range in accepted) {
      if (range.contains(candidate.start) || range.contains(candidate.other)) {
        return true;
      }
    }
    return false;
  }

  int _compareSuffixes(List<_LexToken> tokens, int a, int b) {
    var left = a;
    var right = b;
    while (left < tokens.length && right < tokens.length) {
      final order = tokens[left].normalised.compareTo(tokens[right].normalised);
      if (order != 0) return order;
      left++;
      right++;
    }
    return (tokens.length - a).compareTo(tokens.length - b);
  }

  int _commonPrefix(List<_LexToken> tokens, int a, int b) {
    var length = 0;
    while (a + length < tokens.length && b + length < tokens.length) {
      final left = tokens[a + length].normalised;
      final right = tokens[b + length].normalised;
      if (left != right || left.startsWith('<file:')) break;
      length++;
    }
    return length;
  }

  List<String> _sequence(List<_LexToken> tokens, int start, int length) =>
      tokens
          .skip(start)
          .take(length)
          .map((token) => token.normalised)
          .toList(growable: false);

  String _sequenceKey(List<_LexToken> tokens, int start, int length) =>
      _sequence(tokens, start, length).join('\u{1f}');

  bool _matches(List<_LexToken> tokens, int start, List<String> sequence) {
    if (start + sequence.length > tokens.length) return false;
    for (var i = 0; i < sequence.length; i++) {
      if (tokens[start + i].normalised != sequence[i]) return false;
    }
    return true;
  }
}

class _LexToken {
  const _LexToken(this.normalised, this.file, this.line, this.offset);

  final String normalised;
  final String file;
  final int line;
  final int offset;
}

class _Candidate {
  const _Candidate(this.start, this.other, this.length);

  final int start;
  final int other;
  final int length;
}

class _Occurrence {
  const _Occurrence(this.index, this.file, this.line);

  final int index;
  final String file;
  final int line;
}

class _Range {
  const _Range(this.start, this.end);

  final int start;
  final int end;

  bool contains(int value) => value >= start && value < end;
}
