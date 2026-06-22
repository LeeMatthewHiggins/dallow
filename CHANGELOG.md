# Changelog

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
