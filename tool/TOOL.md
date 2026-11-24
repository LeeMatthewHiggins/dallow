---
name: dallow
description: Codebase intelligence for Dart/Flutter — finds dead code, dependency drift, circular imports, duplicated code, and complexity hot spots. Reads stdout as JSON, SARIF, markdown or text.
platforms:
  linux-amd64:  bin/dallow-linux-amd64
  linux-arm64:  bin/dallow-linux-arm64
  darwin-arm64: bin/dallow-darwin-arm64
---

# dallow

Static codebase intelligence for Dart and Flutter packages, built on the Dart
`analyzer`'s resolved element model (real reachability, not heuristics). Five
checks: reachability-based **dead code**, **dependency hygiene** against
`pubspec.yaml`, **circular imports**, **duplicated code** blocks, and
cyclomatic **complexity** with a project health score.

## Runtime requirement

dallow analyses a package by resolving it against a **Dart SDK**, so a `dart`
must be discoverable at runtime — on `PATH`, via the `DART_SDK` environment
variable, or a Flutter-bundled SDK (`<flutter>/bin/cache/dart-sdk`). On a
workspace without Dart installed the tool exits `69` with a clear message and
writes nothing else. Run it from a Dart/Flutter-capable workspace, and run
`dart pub get` in the target package first so imports resolve.

## Usage

```sh
.dw/tools/dallow/bin/run <command> [path] [flags]
```

`path` defaults to the current directory.

### Commands

| Command | Does |
| --- | --- |
| `analyze` | Run every check (default). |
| `dead-code` | Symbols unreachable from any entrypoint. |
| `deps` | Dependency hygiene: unused, missing, misplaced. |
| `circular` | Import/export cycles between files. |
| `duplication` | Structurally duplicated token blocks. |
| `complexity` | Cyclomatic complexity and a 0–100 project health score with an A–F grade. |

### Flags

| Flag | Values | Default |
| --- | --- | --- |
| `-f, --format` | `console`, `json`, `markdown`, `sarif` | `console` |
| `--fail-on` | `error`, `warning`, `info`, `never` | `error` |
| `-r, --recursive` | Scan every member package of a monorepo (melos, pub workspace, nested pubspecs) | off |
| `--changed-since` | A git ref; report only findings in files changed since it | off |
| `--baseline` | A baseline file; suppress the findings it records | off |
| `--write-baseline` | A file; write current findings as a baseline and exit `0` | off |
| `--max-cycle-size` | Skip import cycles larger than this many files | unlimited |
| `--min-block-size` | Minimum duplicated block size, in tokens | `50` |
| `-c, --config` | A settings file to use instead of the package's `dallow.yaml` | `dallow.yaml` |
| `--include-tests` | Scan test code for duplication (left out by default) | off |
| `--include-generated` | Report findings in generated code (`*.g.dart`, `*.freezed.dart`, banner-marked files) | off |
| `--max-complexity` | Cyclomatic complexity above which a function is reported | `10` |
| `--allow-unresolved` | Analyse despite unresolved files or imports, reporting each as a warning | off |
| `--report-unused-ignores` | Report `dallow-ignore` comments that suppressed nothing | off |

A `dallow.yaml` at the package root can set `exclude` globs, `fail-on`,
per-kind `rules`, ignored dependencies and each threshold; flags override it.

A `// dallow-ignore` or `// dallow-ignore: <kind>` comment on a finding's line,
or the line above it, suppresses that finding.

### Output

`--format json` emits a `{summary, findings[]}` object; each finding carries
`kind`, `severity`, `message`, and (where applicable) `file`, `line`, `symbol`,
`package` (recursive runs)
— line-oriented and stable for agent consumption.

```sh
.dw/tools/dallow/bin/run analyze . --format json
```

### Version

`.dw/tools/dallow/bin/run --version` prints the dallow version and the
`analyzer` version the binary was built with, for example
`dallow 0.4.0 (analyzer 14.7.0)`. Check it first if dallow crashes on new
Dart syntax: an old analyzer cannot read Dart 3.10 dot shorthands.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No findings at or above `--fail-on`. |
| `1` | Findings at or above the `--fail-on` threshold. |
| `64` | Usage error (bad args, missing directory, invalid `dallow.yaml`, unknown git ref, unreadable baseline). |
| `69` | No Dart SDK found at runtime. |
| `78` | A source file or internal import could not be resolved (usually a missing `pub get`). Pass `--allow-unresolved` to continue. |

Idempotent and side-effect free: it only reads the target tree.

## Example

```sh
# Gate a Dart package in CI: fail on any dead code or dependency drift
.dw/tools/dallow/bin/run analyze packages/dw_cli --fail-on warning --format json
```
