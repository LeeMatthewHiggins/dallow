# Changelog

## Unreleased

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
