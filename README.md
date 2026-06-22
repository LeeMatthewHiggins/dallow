# dallow

**Codebase intelligence for Dart and Flutter.** A fast, zero-config CLI that
finds the structural rot `dart analyze` leaves behind: dead code that no
entrypoint can reach, dependency drift in `pubspec.yaml`, and circular imports.

dallow is a Dart-native take on the ideas behind
[fallow](https://github.com/fallow-rs/fallow) (codebase intelligence for
TypeScript/JavaScript). Where fallow approximates reachability syntactically,
dallow builds on the Dart `analyzer`'s **resolved element model** — so the
"what is connected to what?" graph is real, not heuristic.

## What it checks

| Check | What it finds |
| --- | --- |
| **dead-code** | Top-level symbols (functions, classes, enums, mixins, extensions, typedefs, variables) unreachable from any entrypoint. Entrypoints are your `bin/`, `test/`, `example/` files and the public API surface under `lib/`. Only private symbols and `lib/src/` internals are reported — a legitimately-exported public symbol is never flagged as dead. |
| **deps** | Dependencies declared in `pubspec.yaml` but never imported, packages imported but not declared, and dev-dependencies imported from `lib/`. |
| **circular** | Import cycles between files, found as strongly-connected components of the import graph. |

## Install

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
```

### Options

| Flag | Description | Default |
| --- | --- | --- |
| `-f, --format` | `console`, `json`, or `markdown` | `console` |
| `--fail-on` | Lowest severity that exits non-zero: `error`, `warning`, `info`, `never` | `error` |

### Exit codes

`0` when nothing at or above the `--fail-on` threshold is found, `1` otherwise.
This makes dallow a CI gate:

```sh
dallow analyze . --fail-on warning
```

## How it works

1. The package is resolved with the `analyzer`'s `AnalysisContextCollection`,
   giving a fully type-resolved element model.
2. Every top-level declaration becomes a node; resolved references between them
   become edges (synthetic accessors are unwrapped to their backing variable).
3. Entrypoints seed a reachability walk over that graph — anything unreached and
   not part of the public API is a dead-code candidate.
4. `pubspec.yaml` is cross-referenced against the `package:` imports actually
   present in the source tree, and the file-level import graph is scanned for
   cycles.

## Roadmap

- Class-member-level dead code (unused methods and fields).
- Duplication detection (suffix-array over the token stream).
- Architecture boundary rules (layered / feature-first presets).
- Complexity metrics and a project health score.
- Git-diff gating (`--changed-since <ref>`) and baselines, so CI fails only on
  newly introduced findings.
- SARIF output for code-scanning platforms.

## License

MIT — see [LICENSE](LICENSE).
