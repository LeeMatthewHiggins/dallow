import 'dart:typed_data';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dallow/src/finding.dart';
import 'package:dallow/src/util/dart_files.dart';
import 'package:path/path.dart' as p;

/// The smallest duplicate token block worth reporting.
const minDuplicateBlockSize = 4;

/// Default token block size for duplicate code detection.
const defaultDuplicateBlockSize = 50;

/// Detects repeated lexical token sequences across Dart source files.
///
/// The check intentionally stays lexical: identifiers and literals are
/// normalised so structurally identical blocks match, while keywords and
/// punctuation remain exact to keep matches conservative.
class DuplicationCheck {
  const DuplicationCheck();

  /// Scans the Dart files under [rootPath]. A file is left out when
  /// [include], given its package-relative path, returns false.
  List<Finding> run(
    String rootPath, {
    int? minBlockSize,
    bool Function(String relativePath)? include,
  }) {
    final blockSize = minBlockSize ?? defaultDuplicateBlockSize;
    final tokens = _tokensUnder(rootPath, include);
    if (tokens.length < blockSize * 2) return const [];

    return _repeatedBlocks(tokens, blockSize)..sort(compareFindingsByLocation);
  }

  /// The normalised tokens of every included file, each file closed by a
  /// sentinel so that no block spans two files.
  List<_LexToken> _tokensUnder(
    String rootPath,
    bool Function(String relativePath)? include,
  ) {
    final sourceRoot = sourceRootOf(rootPath);
    final tokens = <_LexToken>[];
    for (final path in dartFilesAt(rootPath)) {
      final relativePath = p.relative(path, from: sourceRoot);
      if (include != null && !include(relativePath)) continue;
      tokens
        ..addAll(_scanFile(path, relativePath))
        ..add(_LexToken(_sentinel(path), relativePath, -1, -1));
    }
    return tokens;
  }

  /// One finding per repeated block, longest first, so a block already
  /// reported is not reported again as a shorter block inside it.
  List<Finding> _repeatedBlocks(List<_LexToken> tokens, int blockSize) {
    final index = _SuffixIndex(tokens);
    final candidates = index.candidates(blockSize)
      ..sort((a, b) => b.length.compareTo(a.length));

    final findings = <Finding>[];
    final covered = Uint8List(tokens.length);
    final seen = <int>{};
    for (final candidate in candidates) {
      if (covered[candidate.start] == 1 || covered[candidate.other] == 1) {
        continue;
      }
      final matches = index.matchesOf(candidate);
      if (!seen.add(matches.key)) continue;

      final occurrences = _occurrences(tokens, matches, candidate.length);
      if (occurrences.length < 2) continue;

      for (final occurrence in occurrences) {
        final end = occurrence.index + candidate.length;
        covered.fillRange(occurrence.index, end, 1);
      }
      findings.add(_findingFor(occurrences, candidate.length, blockSize));
    }
    return findings;
  }

  Finding _findingFor(
    List<_Occurrence> occurrences,
    int length,
    int blockSize,
  ) {
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
      weight: length / blockSize,
    );
  }

  /// The non-overlapping places the matched block occurs, in file order.
  List<_Occurrence> _occurrences(
    List<_LexToken> tokens,
    _Matches matches,
    int length,
  ) {
    final occurrences = <_Occurrence>[];

    for (final suffix in matches.starts) {
      final token = tokens[suffix];
      final occurrence = _Occurrence(suffix, token.file, token.line);
      if (_overlapsKept(occurrence, occurrences, length)) continue;
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

  List<_LexToken> _scanFile(String path, String relativePath) {
    final parsed = parseDartFile(path);

    // Directives are excluded: two files that import the same packages are
    // not duplicating each other, and with URIs normalised to `<string>`
    // every import header would otherwise match every other.
    final directives = parsed.unit.directives
        .map((directive) => _Range(directive.offset, directive.end))
        .toList(growable: false);
    // A block that straddles two declarations — the tail of one function
    // and the head of the next — is not a duplicate anyone would extract, so
    // every declaration and member starts with a token unique to it, which
    // no other sequence can match across.
    final boundaries = _declarationStarts(parsed.unit);

    final result = <_LexToken>[];
    Token? token = parsed.unit.beginToken;
    while (token != null && !token.isEof) {
      if (_inside(token.offset, directives)) {
        token = token.next;
        continue;
      }
      if (boundaries.contains(token.offset)) {
        result.add(
          _LexToken(
            '<decl:$relativePath:${token.offset}>',
            relativePath,
            parsed.lineInfo.getLocation(token.offset).lineNumber,
            token.offset,
          ),
        );
      }
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
    if (token.isIdentifier) return _Placeholder.identifier;
    if (_Placeholder.numberTypes.contains(token.type)) {
      return _Placeholder.number;
    }
    if (_Placeholder.stringTypes.contains(token.type)) {
      return _Placeholder.string;
    }
    return token.lexeme;
  }

  String _sentinel(String path) => '<file:${p.normalize(path)}>';

  Set<int> _declarationStarts(CompilationUnit unit) {
    final starts = <int>{};
    for (final declaration in unit.declarations) {
      starts.add(declaration.offset);
      final members = switch (declaration) {
        ClassDeclaration() => declaration.body.members,
        MixinDeclaration() => declaration.body.members,
        EnumDeclaration() => declaration.body.members,
        ExtensionDeclaration() => declaration.body.members,
        ExtensionTypeDeclaration() => declaration.body.members,
        _ => const <ClassMember>[],
      };
      for (final member in members) {
        starts.add(member.offset);
      }
    }
    return starts;
  }

  bool _inside(int offset, List<_Range> ranges) {
    for (final range in ranges) {
      if (range.contains(offset)) return true;
    }
    return false;
  }
}

/// What a token is replaced with before comparison, so that blocks differing
/// only in their names and literal values still match.
abstract final class _Placeholder {
  static const identifier = '<identifier>';
  static const number = '<number>';
  static const string = '<string>';

  static const Set<TokenType> numberTypes = {
    TokenType.INT,
    TokenType.INT_WITH_SEPARATORS,
    TokenType.DOUBLE,
    TokenType.DOUBLE_WITH_SEPARATORS,
    TokenType.HEXADECIMAL,
    TokenType.HEXADECIMAL_WITH_SEPARATORS,
  };

  static const Set<TokenType> stringTypes = {
    TokenType.STRING,
    TokenType.STRING_INTERPOLATION_EXPRESSION,
    TokenType.STRING_INTERPOLATION_IDENTIFIER,
  };
}

/// A suffix array over the normalised token stream, with the length of the
/// prefix each suffix shares with its predecessor.
///
/// Sorting every suffix puts repeated token sequences next to each other, so
/// all occurrences of a block form one contiguous run of the array. Tokens are
/// compared as integer ranks rather than strings, and each run is found by
/// walking the shared-prefix lengths outward — never by rescanning the stream.
class _SuffixIndex {
  _SuffixIndex(List<_LexToken> tokens)
      : _ranks = _rank(tokens),
        _suffixes = Int32List(tokens.length),
        _sharedPrefix = Int32List(tokens.length) {
    for (var i = 0; i < _suffixes.length; i++) {
      _suffixes[i] = i;
    }
    _suffixes.sort(_compareSuffixes);
    for (var i = 1; i < _suffixes.length; i++) {
      _sharedPrefix[i] = _commonPrefix(_suffixes[i - 1], _suffixes[i]);
    }
  }

  /// Each token's rank among the distinct normalised lexemes, in string
  /// order, so comparing two ranks orders tokens exactly as comparing their
  /// text would.
  final Int32List _ranks;

  /// Token offsets, ordered by the suffix starting at each.
  final Int32List _suffixes;

  /// `_sharedPrefix[i]` is how many leading tokens the suffixes at positions
  /// `i - 1` and `i` have in common. File sentinels and declaration markers
  /// are unique, so a shared prefix never crosses a file or a declaration.
  final Int32List _sharedPrefix;

  static Int32List _rank(List<_LexToken> tokens) {
    final lexemes = {for (final token in tokens) token.normalised}.toList()
      ..sort();
    final rankOf = {for (var i = 0; i < lexemes.length; i++) lexemes[i]: i};
    final ranks = Int32List(tokens.length);
    for (var i = 0; i < tokens.length; i++) {
      ranks[i] = rankOf[tokens[i].normalised]!;
    }
    return ranks;
  }

  /// Every adjacent pair of suffixes sharing at least [minLength] tokens.
  List<_Candidate> candidates(int minLength) => [
        for (var i = 1; i < _suffixes.length; i++)
          if (_sharedPrefix[i] >= minLength)
            _Candidate(
              position: i,
              start: _suffixes[i - 1],
              other: _suffixes[i],
              length: _sharedPrefix[i],
            ),
      ];

  /// Every place the block behind [candidate] starts: the run of suffixes
  /// around it that all share at least the candidate's length.
  _Matches matchesOf(_Candidate candidate) {
    final length = candidate.length;
    var first = candidate.position - 1;
    while (first > 0 && _sharedPrefix[first] >= length) {
      first--;
    }
    var last = candidate.position;
    while (last + 1 < _suffixes.length && _sharedPrefix[last + 1] >= length) {
      last++;
    }
    return _Matches(
      key: first * (_suffixes.length + 1) + length,
      starts: Int32List.sublistView(_suffixes, first, last + 1),
    );
  }

  int _compareSuffixes(int a, int b) {
    final count = _ranks.length;
    var left = a;
    var right = b;
    while (left < count && right < count) {
      final order = _ranks[left] - _ranks[right];
      if (order != 0) return order;
      left++;
      right++;
    }
    return (count - a).compareTo(count - b);
  }

  int _commonPrefix(int a, int b) {
    final count = _ranks.length;
    var length = 0;
    while (a + length < count &&
        b + length < count &&
        _ranks[a + length] == _ranks[b + length]) {
      length++;
    }
    return length;
  }
}

/// The occurrences of one repeated block: where each starts, and a [key]
/// shared by every candidate that describes the same block.
class _Matches {
  const _Matches({required this.key, required this.starts});

  final int key;
  final List<int> starts;
}

class _LexToken {
  const _LexToken(this.normalised, this.file, this.line, this.offset);

  final String normalised;
  final String file;
  final int line;
  final int offset;
}

class _Candidate {
  const _Candidate({
    required this.position,
    required this.start,
    required this.other,
    required this.length,
  });

  /// Where the pair sits in the suffix array: [other] is at this position and
  /// [start] at the one before.
  final int position;
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
