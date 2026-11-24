# dallow on open-source projects

What dallow 0.4.0 reports on five well-known Dart and Flutter codebases, run
with default settings: no `dallow.yaml`, no baseline, no suppressions.

Each project was checked out at the revision shown, its dependencies resolved
with `pub get`, and analysed with `dallow analyze` (`-r` for the monorepos) on
an Apple silicon laptop with Dart 3.12.2.

## Results

| Project | Revision | Dart lines | Time | Findings | Health |
| --- | --- | --- | --- | --- | --- |
| [Flutter framework](https://github.com/flutter/flutter) (`packages/flutter`) | 3.44.4 | 1,296,000 | 62 s | 2,850 | 69 (D) |
| [dart_style](https://github.com/dart-lang/dart_style) | 3.1.14 | 31,000 | 10 s | 100 | 81 (B) |
| [Wonderous](https://github.com/gskinnerTeam/flutter-wonderous-app) | `30ccc36` | 31,000 | 17 s | 242 | 75 (C) |
| [bloc](https://github.com/felangel/bloc) (13 packages) | `af38411` | 46,000 | 39 s | 37 | 82–100 |
| [shelf](https://github.com/dart-lang/shelf) (9 packages) | `2856b69` | 13,000 | 15 s | 39 | 53–100 |

Findings by kind:

| Project | Dead code | Cycles | Duplication | High complexity | Dependencies |
| --- | --- | --- | --- | --- | --- |
| Flutter framework | 52 | 9 | 2,076 | 712 | 0 |
| dart_style | 13 | 3 | 34 | 49 | 0 |
| Wonderous | 3 | 2 | 230 | 6 | 0 |
| bloc | 0 | 6 | 15 | 2 | 1 |
| shelf | 1 | 3 | 15 | 10 | 1 |

The findings total also counts one health finding per package.

## What the findings are

### Flutter framework

- **Dead code (52).** All in `lib/src`, all private or internal. Fifteen are
  unused members of the JavaScript interop bindings in `lib/src/web.dart`.
  Most of the rest are getters and setters on private render objects and
  state classes that nothing reads or assigns, such as
  `_RenderSegmentedButton.isExpanded`, whose getter and setter are both
  unused, and `_TextFieldState.needsCounter`.
- **Cycles (9).** The largest spans 283 files; the libraries of `widgets`,
  `rendering` and `material` import each other freely by design.
- **Complexity (712).** 2.2% of 31,806 declared functions exceed a cyclomatic
  complexity of 10, and 226 exceed 20. The highest is `ThemeData.copyWith` at
  86, one branch per optional parameter.
- **Duplication (2,076).** Half is in `lib/src/material`, where widgets and
  their theme classes repeat the same `copyWith`, `lerp`, `==` and
  `debugFillProperties` shapes.

### dart_style

- **Dead code (13).** Debug helpers (`dumpConstraints`, `Code.toCodeTree`) and
  constants in the `Indent` and `Cost` classes that the formatter no longer
  reads.
- **Cycles (3).** One of 45 files covers most of the formatter.
- **Complexity (49).** The highest is `FormatCommand.run` at 39.

### Wonderous

- **Dead code (3).** Two unused style tokens (`_Text.h1`, `_Corners.lg`) and
  one unused method in a developer tool.
- **Duplication (230).** 211 are in `lib/logic/data`, where each wonder is
  described by the same literal structure. An `exclude` entry for that
  directory in `dallow.yaml` leaves 19.
- **Cycles (2).** One of 114 files, which includes the shared
  `common_libs.dart` barrel.

### bloc

- **Dead code (0)** across all thirteen packages and examples.
- **Dependencies (1).** The `replay_bloc` example declares `bloc` and imports
  only `flutter_bloc` and `replay_bloc`.
- **Cycles (6).** Each involves a barrel file that the files it exports
  import back.

### shelf

- **Dead code (1).** `RouterEntry.params` in `shelf_router`, which is exposed
  for the code that `shelf_router_generator` emits.
- **Dependencies (1).** `shelf` declares `path` and never imports it.
- **Health.** The low scores belong to the smallest packages:
  `shelf_static` has 39 functions, three of them over the complexity limit.

## Reading the results

- **Dead-code findings are accurate enough to act on.** A sample of the
  Flutter and dart_style findings was checked against the source by searching
  for references; each was either unused or used only from another package.
- **dallow analyses one package at a time.** A `lib/src` symbol used only by a
  sibling package, like `RouterEntry.params`, is reported. Suppress it with a
  `dallow-ignore` comment or export it.
- **Cycle counts reflect architecture, not defects.** Barrel files and
  mutually dependent layers produce large cycles in healthy codebases.
  `--max-cycle-size` hides the known ones so that new, small cycles stand
  out.
- **Duplication needs tuning per project.** Data tables and families of
  similar classes dominate the default output. `duplication.exclude` and
  `--min-block-size` bring it down to what a team would refactor.
- **Health scores compare a project with itself over time** better than they
  compare projects with each other, and they swing widely for packages with
  only a few dozen functions.
