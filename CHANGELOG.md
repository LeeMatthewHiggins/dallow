# Changelog

## 0.3.0 - 2026-06-28

- Dependencies: upgrade `analyzer` from `^7.0.0` to `^14.0.0`. This migrates the
  symbol graph and dead-code check off the legacy element model onto analyzer's
  unified `Element`/`Fragment` API: source locations and the synthetic-property
  distinction now come from fragments (`firstFragment`, `isOriginDeclaration`),
  declaration nodes are resolved via `declaredFragment` rather than
  `declaredElement`, and `ClassDeclaration`/`EnumDeclaration` names are read from
  their `namePart`. Behaviour is unchanged — all checks produce identical
  findings. No CLI or output changes.

## 0.2.1 - 2026-06-25

- Packaging: add an `example/` (CLI usage walkthrough) and a `.pubignore` that
  drops the `test/` and `tool/` trees from the published archive — the test
  fixtures deliberately import undeclared packages to exercise the deps check,
  which pub flagged as packaging warnings.
- Metadata: broaden the package description to name the duplication and
  complexity checks, add pub.dev `topics`, and declare `issue_tracker`.

## 0.2.0 - 2026-06-25

- Complexity: added a resolved-AST cyclomatic-complexity check for functions,
  methods, constructors, and closures, plus a `complexity` subcommand and
  `--max-complexity` threshold. Findings above the threshold are warnings;
  findings at least twice the threshold are errors.
- Health score: `analyze`/`complexity` now emit an info-level project-health
  finding with a deterministic 0–100 score derived from complexity excess and
  non-complexity finding density.
- PR gate: inline `dallow-ignore` suppression. A `// dallow-ignore` comment on a
  finding's line — or the line directly above it — removes that finding before
  the gate, so it neither prints nor affects the exit code. Scope it to one
  check with `// dallow-ignore: <check-kind>` (a comma-separated list, plus an
  optional trailing reason). Comments are read from the analyzer's token stream
  rather than by scanning text, and suppression composes with `--changed-since`
  and `--baseline` (applied first, against the raw findings).
  `--report-unused-ignores` surfaces stale directives that matched nothing as
  info-level `unused-ignore` findings.
- SARIF output: `--format sarif` emits a SARIF 2.1.0 log for code-scanning
  platforms (e.g. GitHub Advanced Security). The single `run` advertises one
  rule per check kind (`tool.driver.rules`, with a `shortDescription` and a
  `defaultConfiguration.level` mapped from severity — `error`/`warning`/`note`),
  and one `result` per finding (`ruleId` = check kind, mapped `level`, message,
  and a `physicalLocation` with a relative POSIX URI + `region.startLine` only
  when the finding has both a file and a line). Whole-package and
  `pubspec.yaml`-level findings (a file but no line) are emitted as valid
  results without a `physicalLocation`, since GitHub code-scanning needs
  `region.startLine` and would otherwise pin a region-less location to line 1.
  Wired through `--format` on every subcommand.
- PR gate: `--changed-since <ref>` filters findings to files changed since a
  git ref (merge-base `<ref>...HEAD`); whole-package and `pubspec.yaml`
  findings are always kept, and a non-git tree or bad ref exits `64` with a
  clear message instead of crashing.
- PR gate: `--baseline <file>` suppresses findings recorded in a JSON baseline,
  and `--write-baseline <file>` captures the current findings as one (exit `0`),
  so a team can adopt the gate on a dirty codebase and fail only on *new*
  findings. Baseline entries are matched by a line-independent fingerprint
  (kind + file + symbol + normalised message), so they survive line shifts. The
  filters compose and apply to every subcommand.
- Duplication: added a token-level duplicate-code check, `duplication`
  subcommand, `analyze` wiring, and `--min-block-size` threshold.
- Dead code: now reports **unused class members** (methods, getters/setters,
  fields), not just top-level symbols, on the resolved element graph. A member
  is flagged when it is private (or belongs to a non-public-API `lib/src`
  class) and unreachable from any entrypoint. Members reached through
  inheritance — an `@override`, an interface implementation, or a member
  overridden by a subtype — are kept (they may be dispatched dynamically), as
  are public members of public-API classes and fields initialised through a
  `this.x` constructor parameter. Member findings carry a qualified
  `EnclosingType.member` symbol.
- Monorepos: new `-r, --recursive` flag on `analyze` (and every sub-command)
  discovers and analyses all member packages in one run, instead of the
  single-package default. Packages are found from a `melos.yaml` `packages:`
  globs list (honouring `ignore:`), a pub-workspace `workspace:` member list,
  or, failing both, every nested `pubspec.yaml`; build/tooling/symlink dirs are
  skipped. Findings are attributed to their package (console/markdown prefix,
  JSON `package` field) and `--fail-on` is evaluated across all packages.
- Dead code: register Dart 3 `extension type` declarations, so a dead one is
  flagged (labelled "extension type") instead of silently skipped.
- Circular imports: `--max-cycle-size` now rejects values below the smallest
  possible cycle (2) with a usage error, instead of silently disabling the
  check.
- Docs: README exit-codes section now documents `64` (usage) and `69` (no SDK)
  alongside `0`/`1`.
- Build: `tool/build.sh` aborts loudly if no platform binary was produced,
  rather than packaging a binary-less zip.

- Deps: federated plugin implementations (`<base>_web`, `<base>_android`,
  `<base>_platform_interface`, …) are no longer flagged as unused when their
  base plugin is a declared dependency.
- Circular imports: long cycle membership is truncated in the message with an
  "(+N more)" suffix, and a new `--max-cycle-size` flag skips cycles above a
  given size (e.g. a known barrel mega-cycle) while still catching small ones.
- Dead code: skip synthetic elements at registration, so an explicit getter's
  synthetic backing variable is no longer reported as a phantom dead symbol.

- Dead code: seed each public library's export namespace as a reachability
  root, so `lib/src/` symbols surfaced through a barrel re-export are no longer
  false-flagged.
- Dead code: track references made inside `typedef` declarations; symbols used
  only through a typedef are no longer false-flagged.
- Dead code: derive the symbol-kind label from the resolved element type rather
  than `runtimeType.toString()`.
- Deps: anchor the `package:` scan to `import`/`export` directive lines so
  mentions in comments or strings no longer count as usage.
- Circular imports: reworded to "Dependency cycle among N files" (the graph
  includes export edges; members are listed, not a traversal path).
- Extracted the exit-code gate into `exitCodeFor` for direct testing.
- Tests: re-export and typedef regressions, misplaced-dependency, reporters,
  and exit-code gating.

## 0.1.0

Initial release.

- `dead-code`: reachability-based dead-code detection over the resolved
  `analyzer` element graph.
- `deps`: dependency hygiene against `pubspec.yaml` (unused, missing, and
  misplaced dependencies).
- `circular`: import-cycle detection via strongly-connected components.
- `analyze`: runs every check.
- `console`, `json`, and `markdown` output formats with `--fail-on` exit-code
  gating.
