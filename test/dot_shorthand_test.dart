import 'dart:io';

import 'package:dallow/dallow.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Regression for the released binary crashing on Dart 3.10 dot shorthands.
///
/// An analyzer older than 14 cannot write a dot shorthand that sits in a
/// parameter default value or another constant context into its library
/// summary. It throws `Missing implementation of visitDotShorthandInvocation`
/// (or `...PropertyAccess`) and the process exits 255.
///
/// Set `DALLOW_BIN` to a compiled dallow executable to run the end-to-end
/// test against that binary instead of the source (for example, to check a
/// release build before it ships).
void main() {
  final fixture = p.absolute('test', 'fixtures', 'dot_shorthand');

  test('analyze completes on dot shorthands in const contexts', () async {
    final findings = await analyze(fixture, checks: Check.values.toSet());

    expect(
      findings.where((f) => f.kind == CheckKind.projectHealth),
      hasLength(1),
    );
  });

  test(
    'the analyze command exits cleanly on dot shorthands',
    () async {
      final bin = Platform.environment['DALLOW_BIN'];
      final result = bin == null
          ? await Process.run(
              Platform.resolvedExecutable,
              ['run', 'bin/dallow.dart', 'analyze', fixture],
            )
          : await Process.run(bin, ['analyze', fixture]);

      expect(
        result.stderr as String,
        isNot(contains('Missing implementation')),
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
