import 'dart:convert';
import 'dart:io';

import 'package:dallow/src/finding.dart';
import 'package:dallow/src/gate/finding_filter.dart';
import 'package:path/path.dart' as p;

/// Returns the set of files changed between [ref] and `HEAD`, expressed
/// relative to [packageRoot] (the same form a [Finding.file] uses), so the
/// result can be compared directly against findings.
///
/// Uses the merge-base form `git diff --name-only <ref>...HEAD`: it reports
/// what changed on the current branch *since it diverged from* [ref], not
/// every difference between the two tips — exactly the "what did this PR add"
/// question a CI gate asks.
///
/// Changes outside [packageRoot] (siblings in a monorepo) are dropped, and
/// repo-relative paths are rebased onto [packageRoot]. Throws [GateException]
/// — never crashes — when [packageRoot] is not inside a git work tree or [ref]
/// does not resolve to a commit.
Future<Set<String>> changedFilesSince(
  String ref, {
  required String packageRoot,
}) async {
  final toplevel = await _git(
    ['rev-parse', '--show-toplevel'],
    packageRoot,
    onError: (_) => GateException(
      'Not a git repository (or no work tree): $packageRoot\n'
      '--changed-since needs git to compute the changed-file set.',
    ),
  );

  await _git(
    ['rev-parse', '--verify', '--quiet', '$ref^{commit}'],
    packageRoot,
    onError: (_) => GateException(
      "Unknown git ref '$ref'. Pass a branch, tag or commit reachable from "
      'HEAD (e.g. origin/main, a SHA, or HEAD~1).',
    ),
  );

  final out = await _git(
    ['diff', '--name-only', '--diff-filter=d', '$ref...HEAD'],
    packageRoot,
    onError: (stderr) => GateException(
      'git diff against $ref failed: ${stderr.trim()}',
    ),
  );

  final repoTop = toplevel.trim();
  final changed = <String>{};
  for (final line in const LineSplitter().convert(out)) {
    final relPath = line.trim();
    if (relPath.isEmpty) continue;
    // git paths are repo-relative with forward slashes; rebase onto the
    // package root and drop anything that escapes it.
    final abs = p.join(repoTop, relPath);
    if (!p.equals(packageRoot, abs) && !p.isWithin(packageRoot, abs)) continue;
    changed.add(p.relative(abs, from: packageRoot));
  }
  return changed;
}

/// A [FindingFilter] keeping only findings whose file is in [changedFiles].
///
/// Whole-package findings — those with no file location, or dependency-hygiene
/// findings anchored to `pubspec.yaml` — are always kept: they describe the
/// package as a whole, not a line that a diff can attribute. This is the
/// conservative choice (a new whole-package problem still fails the gate).
FindingFilter changedSinceFilter(Set<String> changedFiles) {
  final normalised = changedFiles.map(p.normalize).toSet();
  return (findings) =>
      findings.where((f) => _keep(f, normalised)).toList();
}

bool _keep(Finding finding, Set<String> changedFiles) {
  final file = finding.file;
  if (file == null) return true;
  if (file == 'pubspec.yaml') return true;
  return changedFiles.contains(p.normalize(file));
}

/// Runs `git [args]` in [cwd]. Returns stdout on success; on a non-zero exit
/// throws the [GateException] built by [onError] from the captured stderr.
Future<String> _git(
  List<String> args,
  String cwd, {
  required GateException Function(String stderr) onError,
}) async {
  final ProcessResult result;
  try {
    result = await Process.run('git', args, workingDirectory: cwd);
  } on ProcessException catch (e) {
    throw GateException('Could not run git: ${e.message}');
  }
  if (result.exitCode != 0) {
    throw onError(result.stderr.toString());
  }
  return result.stdout.toString();
}
