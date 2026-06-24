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
| **dead-code** | Top-level symbols (functions, classes, enums, mixins, extensions, typedefs, variables) **and class members** (methods, getters/setters, fields) unreachable from any entrypoint. Entrypoints are your `bin/`, `test/`, `example/` files and the public API surface under `lib/`. Only private symbols and `lib/src/` internals are reported — a legitimately-exported public symbol, or a public member of a public-API class, is never flagged as dead. Members reached through inheritance (an `@override`, an interface implementation, or a member overridden by a subtype) are kept, since they may be dispatched dynamically; a field initialised through a `this.x` constructor parameter counts as used. |
| **deps** | Dependencies declared in `pubspec.yaml` but never imported, packages imported but not declared, and dev-dependencies imported from `lib/`. Federated plugin implementations (`<base>_web`, `<base>_android`, `<base>_platform_interface`, …) are not flagged unused when their base plugin is declared. |
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
| `--max-cycle-size` | Skip import/export cycles with more than this many files — ignore a known barrel mega-cycle while still catching small new ones | unlimited |

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Nothing at or above the `--fail-on` threshold was found |
| `1` | Findings at or above the `--fail-on` threshold |
| `64` | Usage error (bad directory, non-integer or out-of-range `--max-cycle-size`) |
| `69` | No Dart SDK could be located to back the analyzer |

This makes dallow a CI gate:

```sh
dallow analyze . --fail-on warning
```

## How it works

1. The package is resolved with the `analyzer`'s `AnalysisContextCollection`,
   giving a fully type-resolved element model.
2. Every top-level declaration *and class member* becomes a node; resolved
   references between them become edges (synthetic accessors are unwrapped to
   their backing field).
3. Entrypoints seed a reachability walk over that graph — anything unreached and
   not part of the public API is a dead-code candidate. Members reachable
   through inheritance (overrides, interface members) are kept as roots so
   dynamically-dispatched code is never false-flagged.
4. `pubspec.yaml` is cross-referenced against the `package:` imports actually
   present in the source tree, and the file-level import graph is scanned for
   cycles.

## Roadmap

- Duplication detection (suffix-array over the token stream).
- Architecture boundary rules (layered / feature-first presets).
- Complexity metrics and a project health score.
- Git-diff gating (`--changed-since <ref>`) and baselines, so CI fails only on
  newly introduced findings.
- Barrel-cycle collapsing: name the barrel that induces a mega-cycle instead of
  listing every member (today `--max-cycle-size` filters it out).
- SARIF output for code-scanning platforms.

## License

MIT — see [LICENSE](LICENSE).
