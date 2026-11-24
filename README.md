# dallow

[![pub package](https://img.shields.io/pub/v/dallow.svg)](https://pub.dev/packages/dallow)
[![CI](https://github.com/LeeMatthewHiggins/dallow/actions/workflows/ci.yml/badge.svg)](https://github.com/LeeMatthewHiggins/dallow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)

**Codebase intelligence for Dart and Flutter.** A fast CLI that works with no
configuration and finds the structural rot `dart analyze` leaves behind: dead
code that no entrypoint can reach, dependency drift in `pubspec.yaml`, circular
imports, and duplicated code blocks, plus complexity hot spots and an aggregate
project health score.

dallow is a Dart-native take on the ideas behind
[fallow](https://github.com/fallow-rs/fallow) (codebase intelligence for
TypeScript/JavaScript). Where fallow's default analysis is syntactic, dallow
always builds on the Dart `analyzer`'s **resolved element model** — so the
"what is connected to what?" graph is real, not heuristic.

- [doc/open-source-runs.md](doc/open-source-runs.md): what dallow reports on
  the Flutter framework, dart_style, Wonderous, bloc and shelf.
- [doc/fallow-parity.md](doc/fallow-parity.md): a feature-by-feature
  comparison with fallow.

## What it checks

| Check | What it finds |
| --- | --- |
| **dead-code** | Top-level symbols and class members that no entrypoint can reach. Entrypoints are `bin/`, `test/` and `example/` files and the public API under `lib/`. Only private symbols and `lib/src/` internals are reported — see [What counts as used](#what-counts-as-used). |
| **deps** | Dependencies declared in `pubspec.yaml` but never imported, packages imported but not declared, and dev-dependencies imported from `lib/`. Imports are read from parsed directives, so source text held in a string is not counted. Federated plugin implementations (`<base>_web`, `<base>_android`, `<base>_platform_interface`, …) are not flagged unused when their base plugin is declared. |
| **circular** | Import cycles between files, found as strongly-connected components of the import graph. |
| **duplication** | Structurally duplicated Dart token blocks. Identifiers and literals are normalised so copied code with renamed variables still matches; keywords and punctuation stay exact to avoid noisy matches. Directives (`import`, `export`, `part`, `library`) are skipped, so files that share an import header are not reported as duplicating each other. Test code (`test/`, `integration_test/`, `test_driver/`) is left out unless `--include-tests` is passed: tests repeat their arrange-and-assert scaffolding by design. |
| **complexity** | Cyclomatic complexity for functions, methods, constructors, and closures. Complexity starts at `1` per body and adds one for each `if`, `for`, `while`, `do`, `case`, `catch`, `&&`, `||`, `?:`, and `??`. Functions above `--max-complexity` are warnings; functions at least twice the threshold are errors. The check also emits a project [health score](#health-score). |

### What counts as used

The dead-code check prefers a miss to a false alarm. Beyond a direct
reference, a symbol is kept when:

- it is public API: exported from `lib/`, or a public member of an exported
  type or of any supertype of one;
- it takes part in inheritance: it overrides a supertype member, is
  overridden by a subtype, or implements an interface;
- it is used without being named: an operator, a `call()` method, a getter
  read through an object pattern, or a field set through a `this.x`
  constructor parameter;
- it is the counterpart of a reachable symbol in a conditional import
  (`if (dart.library.io) …`), so platform implementations stay alive;
- it is a getter whose setter is in use;
- it is annotated `@pragma('vm:entry-point')`, belongs to a type that is, or
  is a field of a `dart:ffi` `Struct` or `Union`;
- it is referenced from generated code or from an unnamed extension.

A field that is assigned but never read is reported.

### Finding kinds

Every finding carries a stable kind id — shown in `[brackets]` in console
output, as `kind` in JSON, and as `ruleId` in SARIF. It is also the token a
scoped [`dallow-ignore`](#inline-suppression-dallow-ignore) comment takes.

| Kind | Severity | Produced by |
| --- | --- | --- |
| `dead-code` | warning | `dead-code` |
| `unused-dependency` | warning | `deps` |
| `missing-dependency` | error | `deps` |
| `misplaced-dependency` | warning | `deps` |
| `circular-import` | warning | `circular` |
| `duplicate-code` | warning | `duplication` |
| `high-complexity` | warning, or error at twice the threshold | `complexity` |
| `project-health` | info | `complexity` |
| `unresolved-source` | warning | any graph-backed check, with `--allow-unresolved` |
| `unused-ignore` | info | any check, with `--report-unused-ignores` |

## Requirements

dallow resolves the package it analyses against a **Dart SDK** (3.6 or newer),
found on `PATH`, through the `DART_SDK` environment variable, or bundled with
Flutter. Run `dart pub get` (or `flutter pub get`) in the target package first
so its imports resolve.

## Install

```sh
dart pub global activate dallow
```

To run the latest commit instead of the latest release:

```sh
dart pub global activate --source git https://github.com/LeeMatthewHiggins/dallow
```

Or clone and run locally:

```sh
git clone https://github.com/LeeMatthewHiggins/dallow
cd dallow && dart pub get
dart run bin/dallow.dart analyze /path/to/your/package
```

## Usage

```sh
dallow analyze [path]      # run every check (default: current directory)
dallow dead-code [path]    # only reachability-based dead code
dallow deps [path]         # only dependency hygiene
dallow circular [path]     # only circular imports
dallow duplication [path]  # only duplicated token blocks
dallow complexity [path]   # only complexity metrics and health score
```

### Options

| Flag | Description | Default |
| --- | --- | --- |
| `-f, --format` | `console`, `json`, `markdown`, or `sarif` (see [SARIF output](#sarif-output)) | `console` |
| `-r, --recursive` | Scan **every member package** of a monorepo in one run (see [Monorepos](#monorepos)) | off |
| `-c, --config <file>` | Read settings from this file instead of the package's `dallow.yaml` — see [Configuration](#configuration) | `dallow.yaml` |
| `--fail-on` | Lowest severity that exits non-zero: `error`, `warning`, `info`, `never` | `error` |
| `--include-generated` | Report findings located in generated code — see [Generated code](#generated-code) | off |
| `--max-cycle-size` | Skip import/export cycles with more than this many files — ignore a known barrel mega-cycle while still catching small new ones | unlimited |
| `--min-block-size` | Minimum duplicate token block size for `duplication` and `analyze` | `50` |
| `--include-tests` | Scan test code for duplication too. Every other check always covers tests | off |
| `--max-complexity` | Maximum cyclomatic complexity before a function is reported by `complexity` and `analyze` | `10` |
| `--changed-since <ref>` | Only report findings in files changed since a git ref (the merge-base of `<ref>...HEAD`) — see [PR gate](#pr-gate) | off |
| `--baseline <file>` | Suppress findings recorded in a baseline file, so the gate fails only on findings introduced after it was written | off |
| `--write-baseline <file>` | Write the current findings to `<file>` as a baseline and exit `0`, instead of gating | off |
| `--allow-unresolved` | Analyse even when a file or an internal import could not be resolved (normally a missing `pub get`), reporting each gap as an `unresolved-source` warning instead of exiting `78` — see [Exit codes](#exit-codes) | off |
| `--report-unused-ignores` | Emit an info-level `unused-ignore` finding for every `dallow-ignore` comment that suppressed nothing — see [Inline suppression](#inline-suppression-dallow-ignore) | off |

These options apply to every subcommand (`analyze`, `dead-code`, `deps`,
`circular`, `duplication`, `complexity`). A flag always overrides the same
setting in `dallow.yaml`.

### Configuration

dallow needs no configuration, but a `dallow.yaml` at the package root keeps
thresholds, ignored paths and rule severities in the repository instead of on
every command line. Every key is optional:

```yaml
# Files whose findings are never reported.
exclude:
  - lib/l10n/**
  - "*_legacy.dart"

generated:
  report: false        # true reports findings in generated code too
  patterns:            # extra globs marking files as generated
    - "*.gql.dart"

fail-on: warning       # error | warning | info | never

rules:                 # per finding kind: error | warning | info | off
  dead-code: error
  circular-import: off

dependencies:
  ignore:              # packages the deps check never reports
    - build_runner

circular:
  max-cycle-size: 20

duplication:
  min-block-size: 50
  include-tests: false # true scans test/, integration_test/, test_driver/
  exclude:             # left out of duplicate detection only
    - tool/**

complexity:
  max-complexity: 15
```

- **Globs** support `*`, `**`, `?`, `[…]` and `{a,b}`. A pattern without a `/`
  matches a file name at any depth (`*_legacy.dart`); one with a `/` matches
  the path from the package root (`lib/l10n/**`).
- **Excluded files still feed the symbol graph.** Code they reference stays
  reachable; only the findings located in them are dropped.
- **`rules`** takes the [finding kinds](#finding-kinds) as keys. `off` removes
  a kind from the report and from the health score. `unused-ignore` is not
  configurable here: `--report-unused-ignores` controls it.
- **Monorepos**: in a `--recursive` run each member package uses its own
  `dallow.yaml`, falling back to the one at the workspace root. `fail-on` is
  read from the workspace root.
- **`--config <file>`** replaces the lookup with one file, applied to every
  package.

An unknown key, a value of the wrong type or an invalid glob is **rejected
with exit 64** naming the problem, rather than ignored — a typo can never
quietly disable a setting.

### Generated code

Findings located in generated code are left out by default: nobody edits those
files by hand, so their dead helpers, repeated blocks and branchy functions are
noise. A file counts as generated when either:

- its name matches a known generator output — `*.g.dart`, `*.freezed.dart`,
  `*.gr.dart`, `*.mocks.dart`, `*.gen.dart`, and the protobuf family
  (`*.pb.dart`, `*.pbenum.dart`, `*.pbjson.dart`, `*.pbgrpc.dart`,
  `*.pbserver.dart`) — or a glob under `generated.patterns`; or
- its leading comment carries a generated-code banner, such as
  `// GENERATED CODE - DO NOT MODIFY BY HAND` or
  `// Autogenerated …, do not edit`.

Generated files are still resolved into the symbol graph, so a hand-written
symbol referenced only from a `.g.dart` part is **not** reported dead.
Generated functions are also left out of the health score. Dependency checks
are unaffected: an import in a generated file still counts as a use.

Pass `--include-generated`, or set `generated.report: true`, to report on
generated code as well. Generated files must exist on disk — run
`dart run build_runner build` first if they are not committed, otherwise their
`part` directives cannot be resolved and dallow exits `78`.

### Monorepos

By default dallow analyses a single package. Pointed at a monorepo root it would
see only the root and **silently miss** the package-scoped dead-code and
dependency findings of every member. Pass `-r, --recursive` to discover and
analyse all member packages in one run:

```sh
dallow analyze -r .                  # scan the whole workspace
dallow analyze -r --fail-on warning  # CI gate across every package
dallow deps -r .                     # any sub-command works recursively too
```

Member packages are discovered in priority order:

1. a **melos** workspace — `melos.yaml` with `packages:` globs (and an optional
   `ignore:` list);
2. a **pub workspace** — a root `pubspec.yaml` with a `workspace:` member list;
3. otherwise, **every nested `pubspec.yaml`** found by walking the tree.

melos `packages:`/`ignore:` globs support `*` (one path segment), `**` (any
depth), `?` (a single character), and `{a,b}` **brace alternation** — so a
mixed config like `["packages/**", "{examples,e2e}/**"]` selects all three
trees. Any other glob syntax (character classes `[…]`, unbalanced braces) is
**rejected with exit 64** rather than silently matching nothing, so a
misunderstood glob can never produce a falsely-clean report.

Build, tooling and symlink directories (`.dart_tool`, `build`, `.symlinks`, …)
are never treated as packages. Findings are **attributed to their package**: the
console and markdown reports prefix each finding with its package path, and JSON
findings carry a `package` field. The exit code honours `--fail-on` evaluated
**across all packages**.

### Version

`dallow --version` prints the dallow version and the resolved `analyzer`
version, for example `dallow 0.4.0 (analyzer 14.7.0)`. `tool/build.sh` bakes
the analyzer version into each compiled binary.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Nothing at or above the `--fail-on` threshold was found |
| `1` | Findings at or above the `--fail-on` threshold |
| `64` | Usage error (bad directory, bad `--max-cycle-size`, an invalid or unreadable `dallow.yaml`, an unknown `--changed-since` ref, a non-git work tree, or an unreadable baseline) |
| `69` | No Dart SDK could be located to back the analyzer |
| `78` | A source file or an internal import (relative, or `package:<this package>/…`) could not be resolved — usually `pub get` has not been run. Reachability results from such a graph would be silently wrong, so dallow refuses unless `--allow-unresolved` is passed |

This makes dallow a CI gate:

```sh
dallow analyze . --fail-on warning
```

## PR gate

On an established codebase you rarely want to fail CI on the *entire* backlog
of findings — only on what a change actually introduces. Two composable
filters turn dallow into a pull-request gate. Both apply between analysis and
the exit-code decision, and to every subcommand.

### `--changed-since <ref>`: only changed files

```sh
dallow analyze . --changed-since origin/main --fail-on warning
```

This keeps only findings whose file changed relative to `<ref>`, computed as
the merge-base diff `git diff --name-only <ref>...HEAD` — i.e. what your branch
added *since it diverged from* `<ref>`, not every difference between the two
tips. `<ref>` can be a branch, tag, or SHA (`origin/main`, `HEAD~1`, …).

Findings that aren't tied to a single source line — whole-package signals with
no file, and dependency-hygiene findings against `pubspec.yaml` — are **always
kept**, so a newly broken dependency still fails the gate. A finding that sits
*unchanged* in a file you *did* touch is also kept: filtering is at file
granularity. If the
package isn't inside a git work tree, or `<ref>` doesn't resolve, dallow prints
a clear message to stderr and exits `64` rather than crashing.

### `--baseline <file>`: ignore a known backlog

Adopt the gate on a dirty codebase in two steps. First, capture today's
findings as a baseline (this writes the file and exits `0`):

```sh
dallow analyze . --write-baseline .dallow-baseline.json
```

Then have CI run against it — only findings *not* in the baseline gate:

```sh
dallow analyze . --baseline .dallow-baseline.json --fail-on warning
```

Each baselined finding is matched by a **fingerprint** derived from its kind,
file, symbol and normalised message — deliberately **not** its line number — so
a finding keeps its identity when unrelated edits shift it up or down its file.
Commit the baseline; regenerate it with `--write-baseline` after you burn the
backlog down. The two flags compose: `--changed-since origin/main --baseline
.dallow-baseline.json` gates only on new findings, in changed files, that
aren't already baselined.

### Inline suppression (`dallow-ignore`)

When a single finding is a deliberate, reviewed exception, silence it in place
with a `dallow-ignore` comment instead of carrying it in the baseline. The
comment goes **on the finding's line** or **on the line directly above it**:

```dart
// dallow-ignore
void _legacyEntryPoint() {} // kept for the old plugin ABI

void _debugDump() {} // dallow-ignore: dead-code
```

- **Unscoped** — `// dallow-ignore` suppresses *every* finding on its target
  line.
- **Scoped** — `// dallow-ignore: <check-kind>` suppresses only that kind; pass
  a comma-separated list (`dallow-ignore: dead-code, duplicate-code`) for
  several. The kind is the stable id shown in `[brackets]` in console output
  (`dead-code`, `duplicate-code`, `unused-dependency`, …). Anything after the
  kinds is treated as a free-text reason.

Suppressed findings are removed **before** the gate, so they neither print nor
affect the exit code — exactly like a baselined finding. Suppression composes
with `--changed-since` and `--baseline`; it is applied first, against the raw
findings. Comments are read from the analyzer's own token stream, not by
scanning text, so a `dallow-ignore` inside a string literal is not a directive.

Whole-package findings (no source line — a missing dependency, say) can't be
annotated on a line and so can't be suppressed this way; baseline them instead.

A directive that matches nothing — typically one left behind after the finding
it silenced was fixed — is silently ignored by default. Pass
`--report-unused-ignores` to surface each as an info-level `unused-ignore`
finding so stale directives can be cleaned up (they gate only under
`--fail-on info`).

## Use as a library

The checks behind the CLI are exported from `package:dallow/dallow.dart`, so a
custom tool or test can run them directly:

```dart
import 'package:dallow/dallow.dart';

Future<void> main() async {
  final findings = await analyze('.', checks: Check.values.toSet());
  print(Reporter(ReportFormat.markdown).render(findings));
}
```

`analyze` covers one package and `analyzeWorkspace` every member of a monorepo.
Both read the package's `dallow.yaml` unless given a `config:` (a
`DallowConfig`, for instance `DallowConfig.defaults` to ignore the file).
Without an explicit `checks:` set they run dead code, dependencies, circular
imports and duplication; pass `Check.values.toSet()` to add complexity and the
health score, as the `dallow analyze` command does. See
[example/example.dart](example/example.dart) for a runnable version.

## SARIF output

`--format sarif` emits a [SARIF 2.1.0](https://sarifweb.azurewebsites.net/) log
— the standard interchange format for static-analysis results — so dallow's
findings can be uploaded to a code-scanning platform (GitHub Advanced Security,
Azure DevOps, …) and rendered as inline annotations on a pull request.

```sh
dallow analyze . --format sarif > dallow.sarif
```

The log contains a single `run`. Its `tool.driver` advertises **one rule per
check kind** (`dead-code`, `unused-dependency`, `circular-import`, …), each with
a `shortDescription` and a `defaultConfiguration.level` mapped from the check's
severity (`error` → `error`, `warning` → `warning`, `info` → `note`). Each
finding becomes one `result`, with `ruleId` set to its check kind, the same
mapped `level`, the finding message, and — when the finding is tied to a source
line — a `physicalLocation` carrying a relative POSIX `artifactLocation.uri` and
a `region.startLine`. Whole-package signals (no file) and `pubspec.yaml`-level
dependency findings (a file but no single source line) are emitted as valid
results **without** a `physicalLocation` rather than being dropped: GitHub
code-scanning needs `region.startLine` to place an annotation, so a location
with a file but no region would be pinned to line 1 — these findings name the
file they concern in the result message instead of inventing that line.

In a GitHub Actions workflow, upload the file with
[`github/codeql-action/upload-sarif`](https://github.com/github/codeql-action):

```yaml
- run: dallow analyze . --format sarif > dallow.sarif
- uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: dallow.sarif
```

## How it works

1. The package is resolved with the `analyzer`'s `AnalysisContextCollection`,
   giving a fully type-resolved element model.
2. Every top-level declaration *and class member* becomes a node; resolved
   references between them become edges (synthetic accessors are unwrapped to
   their backing field).
3. Entrypoints seed a reachability walk over that graph — anything unreached and
   not part of the public API is a dead-code candidate.
4. `pubspec.yaml` is cross-referenced against the `package:` imports actually
   present in the source tree, and the file-level import graph is scanned for
   cycles.
5. Dart source files are tokenised with the analyzer scanner, normalised, and
   compared with a suffix array to find repeated token blocks. Tokens are
   ranked as integers and each block's occurrences are read off the array as
   one contiguous run, so the check stays fast on large packages.
6. Function-like bodies already available in the resolved AST are walked for
   cyclomatic complexity, which feeds the [health score](#health-score).
7. The same token stream is read for `dallow-ignore` comments, which suppress
   matching findings before the gate runs.

## Health score

The `complexity` check reports a score from 0 to 100 and a grade: A from 90,
B from 80, C from 70, D from 60, otherwise F.

```text
score = clamp(0, 100, 100 - complexityPenalty - findingsPenalty)

complexityPenalty = min(60, round(4 * 100 * overLimit / declaredFunctions))
findingsPenalty   = min(40, round(100 * weightedFindings / declaredFunctions))
```

- **`declaredFunctions`** counts functions, methods and constructors.
  Closures are measured for complexity but left out of this count, so a
  codebase full of one-line callbacks does not dilute its problems.
- **`overLimit`** counts each function over `--max-complexity` once, or twice
  when it is at least double the limit. Four points are lost for each percent
  of functions over the limit.
- **`weightedFindings`** sums the findings of the other enabled checks: 2 for
  an error, 1 for a warning, 0.25 for an info. A duplicated block is further
  multiplied by `blockTokens / minBlockSize`, so a copied 800-token function
  costs sixteen times a repeated 50-token block. One point is lost for each
  weighted finding per hundred functions.

The health message reports every input. Because both penalties are
proportional, a package with a few dozen functions moves further on a single
finding than a large one.

## Roadmap

The gaps against fallow are tracked in
[doc/fallow-parity.md](doc/fallow-parity.md). The next ones planned:

- Architecture boundary rules (layered / feature-first presets).
- Auto-fix for unused dependencies and unused private symbols.
- Barrel-cycle collapsing: name the barrel that induces a large cycle instead
  of listing every member.

## Contributing

Issues and pull requests are welcome at
<https://github.com/LeeMatthewHiggins/dallow/issues>. Before opening a pull
request, run `dart format .`, `dart analyze` and `dart test`.

## License

MIT — see [LICENSE](LICENSE).
