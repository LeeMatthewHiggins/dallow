# dallow

**Codebase intelligence for Dart and Flutter.** A fast, zero-config CLI that
finds the structural rot `dart analyze` leaves behind: dead code that no
entrypoint can reach, dependency drift in `pubspec.yaml`, circular imports, and
duplicated code blocks.

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
| **duplication** | Structurally duplicated Dart token blocks. Identifiers and literals are normalised so copied code with renamed variables still matches; keywords and punctuation stay exact to avoid noisy matches. |

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
dallow duplication [path]  # only duplicated token blocks
```

### Options

| Flag | Description | Default |
| --- | --- | --- |
| `-f, --format` | `console`, `json`, or `markdown` | `console` |
| `--fail-on` | Lowest severity that exits non-zero: `error`, `warning`, `info`, `never` | `error` |
| `--max-cycle-size` | Skip import/export cycles with more than this many files — ignore a known barrel mega-cycle while still catching small new ones | unlimited |
| `--min-block-size` | Minimum duplicate token block size for `duplication` and `analyze` | `20` |
| `--changed-since <ref>` | Only report findings in files changed since a git ref (the merge-base of `<ref>...HEAD`) — see [PR gate](#pr-gate) | off |
| `--baseline <file>` | Suppress findings recorded in a baseline file, so the gate fails only on findings introduced after it was written | off |
| `--write-baseline <file>` | Write the current findings to `<file>` as a baseline and exit `0`, instead of gating | off |

These options apply to every subcommand (`analyze`, `dead-code`, `deps`,
`circular`).

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Nothing at or above the `--fail-on` threshold was found |
| `1` | Findings at or above the `--fail-on` threshold |
| `64` | Usage error (bad directory, bad `--max-cycle-size`, an unknown `--changed-since` ref, a non-git work tree, or an unreadable baseline) |
| `69` | No Dart SDK could be located to back the analyzer |

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
*unchanged* in a file you *did* touch is also kept (filtering is at file
granularity; line-level diffing is a possible future refinement). If the
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
5. Dart source files are tokenised with the analyzer scanner, normalised, and
   compared with a suffix array to find repeated token blocks.

## Roadmap

- Architecture boundary rules (layered / feature-first presets).
- Complexity metrics and a project health score.
- Barrel-cycle collapsing: name the barrel that induces a mega-cycle instead of
  listing every member (today `--max-cycle-size` filters it out).
- SARIF output for code-scanning platforms.

## License

MIT — see [LICENSE](LICENSE).
