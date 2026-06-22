# Changelog

## Unreleased

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
