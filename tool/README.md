# dallow — Digital Workforce tool package

This directory packages [dallow](https://github.com/LeeMatthewHiggins/dallow)
as a Digital Workforce **tool** workspace item: native binaries plus a
`TOOL.md` manifest, provisioned to agent workspaces under
`.dw/tools/dallow/` with a `bin/run` shim.

## Build

`build.sh` compiles a binary per platform and assembles the flat zip:

```sh
tool/build.sh
# → build/dallow-tool.zip
```

It produces `darwin-arm64` natively and `linux-amd64` / `linux-arm64` via
Docker (`dart:stable`). Only the platforms it successfully builds are written
into the `platforms:` map of the packaged `TOOL.md`.

## Publish

`dw tool create` runs in agent mode (it needs an execution credential and task
id) or a human uploads the zip via the admin UI (`/workspace-items/add`):

```sh
dw tool create \
  --title "dallow" \
  --description "Codebase intelligence for Dart/Flutter: dead code, dependency hygiene, circular imports." \
  --zip-file build/dallow-tool.zip \
  --context organisation --entity-id <orgId>
```

Narrowest scope wins on a slug collision; the provisioned slug is the
manifest `name:` (`dallow`), matched to `--title`.
