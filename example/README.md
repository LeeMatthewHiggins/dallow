# dallow examples

dallow is a command-line tool, so the examples below are invocations rather
than a Dart `main()`. Activate it once, then run it against any Dart or Flutter
package.

```sh
dart pub global activate dallow
```

## Analyse a package

Run every check against the current directory:

```sh
dallow analyze
```

…or point it at a path:

```sh
dallow analyze path/to/your/package
```

## Run a single check

```sh
dallow dead-code      # reachability-based dead code
dallow deps           # dependency hygiene (unused / missing / misplaced)
dallow circular       # import cycles
dallow duplication    # duplicated token blocks
dallow complexity     # cyclomatic complexity + project health score
```

## Gate a pull request

Fail CI only on findings a branch *introduces*, ignoring the existing backlog:

```sh
dallow analyze . --changed-since origin/main --fail-on warning
```

Or adopt the gate on a dirty codebase with a baseline:

```sh
dallow analyze . --write-baseline .dallow-baseline.json   # capture today's findings
dallow analyze . --baseline .dallow-baseline.json --fail-on warning
```

## Scan a monorepo

Analyse every member package (melos / pub-workspace / nested) in one run:

```sh
dallow analyze -r . --fail-on warning
```

## Emit SARIF for code scanning

```sh
dallow analyze . --format sarif > dallow.sarif
```

See the [package README](../README.md) for the full flag reference, exit
codes, and inline `dallow-ignore` suppression.
