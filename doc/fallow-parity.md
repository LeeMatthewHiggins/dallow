# dallow and fallow: feature parity

dallow is a Dart-native take on [fallow](https://github.com/fallow-rs/fallow),
the codebase-intelligence CLI for TypeScript and JavaScript. This page compares
dallow 0.4.0 with fallow 3.45.0 (released
2026-11-20), based on fallow's README and its documentation at
<https://fallow.tools/docs/>.

fallow has grown well beyond its dead-code origins: 46 subcommands and roughly
136 documented issue types. Much of that is specific to the JavaScript
ecosystem. The comparison below therefore separates three things: what dallow
already matches, what it is missing and should gain, and what does not
translate to Dart.

Status key: **Yes** means equivalent, **Partial** means the core is present
with gaps listed, **No** means missing.

## Summary

| Area | Parity | Biggest gap |
| --- | --- | --- |
| Dead code | Partial | No unused-file kind, no per-kind filters |
| Generated code and entrypoints | Partial | Annotation-driven entrypoints beyond `vm:entry-point` |
| Dependency hygiene | Partial | No unused dev-dependency or test-only checks |
| Circular imports | Yes | No package-level cycles in a workspace |
| Duplication | Partial | One normalisation mode, no percentage gate |
| Configuration file | Partial | No `extends`, no per-path overrides, no `init` |
| Complexity and health | Partial | Cyclomatic only; no cognitive, hotspots or targets |
| PR gate | Partial | No regression gate, no staged or diff-file input |
| Suppression | Partial | No file-level or range comments |
| Output formats | Partial | No compact, Code Climate or PR-comment formats |
| Monorepos | Partial | No workspace filter, per-package graphs only |
| Auto-fix | No | |
| Architecture boundaries | No | |
| Editor, agent and CI integrations | No | |
| Inspection commands | No | No `list`, `explain`, `trace` or `inspect` |

## Where dallow is ahead

- **Resolved analysis by default.** dallow always works from the Dart
  analyzer's resolved element model. fallow's default analysis is syntactic,
  with a TypeScript checker available as an opt-in `--type-aware` companion.
- **Member-level dead code as standard.** Unused methods, getters, setters and
  fields are reported with inheritance and dynamic dispatch accounted for.
  fallow removes an unused class member only after type-aware analysis.
- **Refusal on an unresolved graph.** dallow exits `78` rather than report
  dead code from a graph with holes. fallow reports `unresolved-import` as a
  finding and carries on.

## Checks

### Dead code

| fallow | dallow | Status |
| --- | --- | --- |
| `unused-export`, `unused-type` | `dead-code` for unreachable top-level symbols | Yes |
| `unused-class-member`, `unused-enum-member` | `dead-code` for class members | Partial: enum values are not tracked individually |
| `unused-file` | A dead file shows up as one finding per symbol | No |
| `unresolved-import` | `unresolved-source`, or exit `78` | Yes |
| `duplicate-export` | None | No |
| `private-type-leak`, `deprecated-export-in-use` (opt-in) | None | No |
| Per-kind filter flags (`--unused-files`, `--unused-exports`) | None; every dead symbol shares one kind | No |
| `--include-entry-exports`, `publicPackages` | Public API is always treated as an entrypoint | No |
| `--production` mode | None; `test/` and `example/` are always entrypoints | No |
| Component, store, server-action and Svelte findings | Not applicable to Dart | — |

The Dart counterpart of fallow's framework plugins is awareness of generated
code and of entrypoints declared by annotation. dallow leaves findings in
generated files (`*.g.dart`, `*.freezed.dart`, banner-marked files, …) out of
the report while still resolving them into the graph, and treats
`@pragma('vm:entry-point')` as an entrypoint. It has no plugin mechanism, so
other annotation-driven entrypoints (route generators, dependency-injection
registrations that are not yet generated) are not recognised.

### Dependencies

| fallow | dallow | Status |
| --- | --- | --- |
| `unused-dependency` | `unused-dependency` | Yes |
| `unlisted-dependency` | `missing-dependency` | Yes |
| `dev-dependency-in-production` | `misplaced-dependency` | Yes |
| `unused-dev-dependency` | None | No |
| `test-only-dependency` | None | No |
| `unlisted-binary` | None; `executables:` is not cross-checked | No |
| `ignoreDependencies` config | `dependencies.ignore` | Yes |
| pnpm catalog and override rules, `type-only-dependency` | Not applicable to Dart | — |

A pub workspace equivalent worth considering is drift between member packages
that pin different constraints for the same dependency.

### Architecture

| fallow | dallow | Status |
| --- | --- | --- |
| `circular-dependency` | `circular-import` | Yes |
| `re-export-cycle` | Export edges are part of the cycle graph | Partial: not reported separately |
| `package-cycle` | None | No |
| `circularDependencies.allow` | `--max-cycle-size` | Partial |
| `boundary-violation`, zones, rules, four presets | None | No |
| `fallow guard`, rule packs, `policy-violation` | None | No |

### Duplication

| fallow | dallow | Status |
| --- | --- | --- |
| `code-duplication` | `duplicate-code` | Yes |
| Modes `strict`, `mild`, `weak`, `semantic` | One mode, equal to `semantic` (identifiers and literals normalised) | Partial |
| `--min-tokens` (default 50) | `--min-block-size` (default 50) | Yes |
| `--min-lines` (5), `--min-occurrences` (2) | None | No |
| `--threshold <pct>` duplication-percentage gate | None | No |
| `--near` near-miss clones | None | No |
| `--skip-local` cross-directory only | None | No |
| Imports ignored by default | Directives are skipped | Yes |
| Tests, mocks and build output ignored by default | Test directories and generated code are skipped by default; `--include-tests` opts back in | Yes |
| Stable `dup:<hash>` handles, clone families, extract suggestions | A fingerprint is used by the baseline only | No |

With the same defaults as fallow — a 50-token minimum and tests left out —
dallow's duplication output is comparable in volume. See
[open-source-runs.md](open-source-runs.md) for counts on real projects.

### Complexity and health

| fallow | dallow | Status |
| --- | --- | --- |
| Cyclomatic complexity, `--max-cyclomatic` (default 20) | `--max-complexity` (default 10) | Yes |
| Cognitive complexity, `--max-cognitive` | None | No |
| CRAP score, coverage input (`--coverage`) | None; lcov is not read | No |
| `long-file`, unit-size limit | None | No |
| Health score 0–100 with letter grade | Health score 0–100 with an A–F grade, from complexity and finding density | Partial: fewer inputs than fallow's |
| Maintainability index, per-file scores | None | No |
| Hotspots from git churn, change coupling | None | No |
| Refactoring targets | None | No |
| Ownership and bus factor | None | No |
| Snapshots and trend (`--save-snapshot`, `--trend`) | None | No |
| `--min-score` gate, SVG badge | None | No |
| CSS analytics, runtime coverage, mutation testing | Not planned | — |

## Workflow

### Gating and baselines

| fallow | dallow | Status |
| --- | --- | --- |
| `--changed-since <ref>` | `--changed-since <ref>` | Yes |
| `--baseline`, `--save-baseline` | `--baseline`, `--write-baseline` | Yes |
| `--fail-on-issues`, `--ci` | `--fail-on <severity>` | Yes |
| `--diff-file`, `--diff-stdin`, `--staged` | None | No |
| Line-level "new only" gating (`audit --gate new-only`) | File-level only | Partial |
| `--fail-on-regression`, `--tolerance`, regression baselines | None | No |
| `--baseline-mode count`, stale-baseline and growth gates, `baselines prune` | Identity matching only | Partial |
| Rule severities in config (`error`, `warn`, `off`) | `rules:` in `dallow.yaml` (`error`, `warning`, `info`, `off`) | Yes |
| Exit codes `0`, `1`, `2` | `0`, `1`, `64`, `69`, `78` | Different by design |

### Suppression

| fallow | dallow | Status |
| --- | --- | --- |
| `// fallow-ignore-next-line [kinds]` | `// dallow-ignore[: kinds]` on the line or the line above | Yes |
| `// fallow-ignore-file [kinds]` | None | No |
| `fallow-ignore-start` / `-end` ranges for duplication | None | No |
| `stale-suppression` (on by default) | `unused-ignore` behind `--report-unused-ignores` | Yes |
| `missing-suppression-reason` (opt-in) | Reason text is accepted, never required | Partial |
| `@public`, `@internal`, `@expected-unused` doc tags | None; `package:meta` annotations are not read | No |
| `fallow suppressions` inventory | None | No |

### Output

| fallow | dallow | Status |
| --- | --- | --- |
| `human`, `json`, `markdown`, `sarif` | `console`, `json`, `markdown`, `sarif` | Yes |
| `compact` | None | No |
| `codeclimate` for GitLab Code Quality | None | No |
| `github-annotations`, `github-summary`, PR and MR comment formats | None | No |
| `badge` | None | No |
| `--output-file`, `--quiet`, `--summary`, `--group-by` | Output goes to stdout only | No |
| Stable `finding_id`, `actions[]` and `next_steps` in JSON | `kind`, `severity`, `message`, `file`, `line`, `symbol`, `package` | Partial |
| Published JSON output schema | None | No |

### Monorepos

| fallow | dallow | Status |
| --- | --- | --- |
| Workspace discovery (npm, pnpm, Yarn, Bun, Deno) | melos, pub workspaces, nested pubspecs via `-r` | Yes |
| One module graph across all packages | One graph per package | Partial |
| `--workspace <name or glob>` | None | No |
| `--changed-workspaces <ref>` | None | No |
| `--group-by package` | Findings carry a `package` field | Yes |
| Per-package config and baselines | Per-package `dallow.yaml` with a workspace-root fallback; no per-package baselines | Partial |
| `fallow workspaces` diagnostics | The strategy and package count go to stderr | Partial |

### Configuration

fallow reads `.fallowrc.json`, `.fallowrc.jsonc`, `fallow.toml` or
`.fallow.toml`, with `extends`, per-rule severities, per-path `overrides`,
`entry` and `ignorePatterns`, ignore lists for dependencies and exports, and
sections for duplication, health and boundaries. `fallow init` writes a
starter file and `fallow config` prints the resolved result.

dallow reads a `dallow.yaml` at the package root (or the file named by
`--config`), falling back to the workspace root in a recursive run. It covers
the same ground for the checks dallow has:

| fallow | dallow | Status |
| --- | --- | --- |
| `ignorePatterns` | `exclude` | Yes |
| `rules` | `rules` | Yes |
| `ignoreDependencies` | `dependencies.ignore` | Yes |
| `duplicates.minTokens`, `duplicates.ignore`, `duplicates.ignoreDefaults` | `duplication.min-block-size`, `duplication.exclude`, `duplication.include-tests` | Yes |
| `health.maxCyclomatic` | `complexity.max-complexity` | Yes |
| Unknown keys are a hard error | Unknown keys exit `64` | Yes |
| `entry`, `dynamicallyLoaded` | None; entrypoints are inferred, plus `vm:entry-point` | No |
| `overrides[] {files, rules}` | None | No |
| `extends` | None | No |
| `ignoreExports`, `ignoreFindings` | `dallow-ignore` comments and baselines only | No |
| `FALLOW_*` environment variables | None | No |
| `fallow init`, `fallow config`, published JSON schema | None | No |

### Commands

| fallow | dallow | Status |
| --- | --- | --- |
| bare `fallow` runs everything | `dallow analyze` | Yes |
| `dead-code`, `dupes`, `health` | `dead-code`, `deps`, `circular`, `duplication`, `complexity` | Yes |
| `--only`, `--skip` | One subcommand per check | Partial |
| `audit`, `review` | `analyze --changed-since` | Partial |
| `fix` with `--dry-run` | None | No |
| `watch` | None | No |
| `init`, `config`, `doctor` | None | No |
| `list` (entry points, files, workspaces) | None | No |
| `explain <issue-type>` | None | No |
| `trace`, `inspect`, `impact` | None | No |
| `migrate` (from knip, jscpd) | None | No |
| `schema` capability manifest | None | No |
| `flags`, `security`, `similar-code`, `mutation`, `viz`, `coverage`, `cloud`, `license` | Not planned | — |

### Integrations

| fallow | dallow | Status |
| --- | --- | --- |
| GitHub Action (`fallow-rs/fallow@v3`) | SARIF upload documented in the README | Partial |
| GitLab CI template | None | No |
| LSP server and VS Code extension | None | No |
| MCP server (`fallow-mcp`) | None | No |
| Git and agent hooks (`fallow hooks install`) | None | No |
| Node bindings | `package:dallow/dallow.dart` library API | Yes |
| 156 framework plugins | None | No |
| Incremental parse cache | None; each run resolves from scratch | No |
| npm, cargo, Homebrew, Docker | `dart pub global activate`, compiled binaries from `tool/build.sh` | Partial |

## Suggested order of work

Ordered by how much each closes the gap for a typical Dart or Flutter team.

1. **Configuration depth.** Per-path `overrides`, declared `entry` points,
   and an `init` command that writes a starter `dallow.yaml`.
2. **Annotation-driven entrypoints.** Generated code and
   `@pragma('vm:entry-point')` are handled; a configurable list of
   annotations that mark a symbol as used would cover the remaining
   false positives in Flutter apps.
3. **Duplication gates.** `--min-lines` and a `--threshold` percentage gate.
4. **File-level and range suppression**, plus an `unused-file` kind so a dead
   file is one finding instead of many.
5. **Auto-fix** for the safe cases: unused dependencies in `pubspec.yaml` and
   unused private top-level symbols, with `--dry-run`.
6. **Architecture boundaries** with layered and feature-first presets.
7. **Cognitive complexity and hotspots.** Churn multiplied by complexity is
   fallow's most actionable health output.
8. **CI formats**: `github-annotations` and `codeclimate`, plus a published
   GitHub Action wrapping the SARIF flow.
9. **Workspace filters** (`--workspace`, `--changed-workspaces`) and a
   cross-package graph, so a symbol used only by a sibling package's tests is
   handled correctly.
10. **Editor and agent integrations.** An `analysis_server_plugin` would
    surface findings in every Dart IDE without a separate LSP server; an MCP
    server is the equivalent for coding agents.

## Not applicable to Dart

These fallow features have no meaningful Dart counterpart and are not gaps:
component-prop, store, server-action and Svelte findings; route collision and
client/server directive rules; pnpm catalog and override rules; CSS and
Tailwind analytics; TS-to-JS cross-language duplication; `type-only`
dependencies; and the licensed runtime-coverage and cloud products.
