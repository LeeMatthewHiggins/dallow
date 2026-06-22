---
name: dallow
description: Codebase intelligence for Dart/Flutter — finds dead code, dependency hygiene problems, and circular imports. Reads stdout as JSON or text.
platforms:
  linux-amd64:  bin/dallow-linux-amd64
  linux-arm64:  bin/dallow-linux-arm64
  darwin-arm64: bin/dallow-darwin-arm64
---

# dallow

Static codebase intelligence for Dart and Flutter packages, built on the Dart
`analyzer`'s resolved element model (real reachability, not heuristics). Three
checks: reachability-based **dead code**, **dependency hygiene** against
`pubspec.yaml`, and **circular imports**.

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

### Flags

| Flag | Values | Default |
| --- | --- | --- |
| `-f, --format` | `console`, `json`, `markdown` | `console` |
| `--fail-on` | `error`, `warning`, `info`, `never` | `error` |

### Output

`--format json` emits a `{summary, findings[]}` object; each finding carries
`kind`, `severity`, `message`, and (where applicable) `file`, `line`, `symbol`
— line-oriented and stable for agent consumption.

```sh
.dw/tools/dallow/bin/run analyze . --format json
```

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | No findings at or above `--fail-on`. |
| `1` | Findings at or above the `--fail-on` threshold. |
| `64` | Usage error (bad args / missing directory). |
| `69` | No Dart SDK found at runtime. |

Idempotent and side-effect free: it only reads the target tree.

## Example

```sh
# Gate a Dart package in CI: fail on any dead code or dependency drift
.dw/tools/dallow/bin/run analyze packages/dw_cli --fail-on warning --format json
```
