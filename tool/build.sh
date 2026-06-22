#!/usr/bin/env bash
# Builds the dallow Digital Workforce tool zip: one native binary per platform
# plus the TOOL.md manifest, assembled flat with TOOL.md at the zip root.
#
# darwin-arm64 is compiled natively; linux-amd64 / linux-arm64 are compiled in
# the dart:stable container. The packaged platforms: map lists only binaries
# that actually built, so a missing toolchain degrades gracefully.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$repo_root/build/stage"
out_zip="$repo_root/build/dallow-tool.zip"

rm -rf "$stage" "$out_zip"
mkdir -p "$stage/bin"

echo "==> darwin-arm64 (native)"
if [[ "$(uname -sm)" == "Darwin arm64" ]]; then
  (cd "$repo_root" && dart pub get >/dev/null && \
    dart compile exe bin/dallow.dart -o "$stage/bin/dallow-darwin-arm64")
else
  echo "   skipped (host is not Darwin arm64)"
fi

build_linux() {
  local arch="$1" platform="$2"
  echo "==> linux-$arch (docker $platform)"
  docker run --rm --platform "$platform" \
    -v "$repo_root:/src:ro" -v "$stage/bin:/out" -w /work \
    dart:stable bash -c "cp -r /src/. /work && rm -rf /work/.dart_tool /work/build && \
      dart pub get >/dev/null && \
      dart compile exe bin/dallow.dart -o /out/dallow-linux-$arch"
}

build_linux amd64 linux/amd64 || echo "   linux-amd64 build failed, skipping"
build_linux arm64 linux/arm64 || echo "   linux-arm64 build failed, skipping"

# Without nullglob an empty bin/ would leave the literal `dallow-*` in the
# platforms: map and ship a binary-less zip; abort loudly instead.
shopt -s nullglob
binaries=("$stage"/bin/dallow-*)
if [[ ${#binaries[@]} -eq 0 ]]; then
  echo "error: no binaries built for any platform; refusing to package an empty tool zip" >&2
  exit 1
fi

echo "==> assembling zip"
cp "$repo_root/LICENSE" "$repo_root/README.md" "$stage/"

# Manifest body (everything after the closing frontmatter ---) is reused; the
# platforms: map is regenerated from the binaries that actually built.
{
  echo "---"
  echo "name: dallow"
  echo "description: Codebase intelligence for Dart/Flutter — finds dead code, dependency hygiene problems, and circular imports. Reads stdout as JSON or text."
  echo "platforms:"
  for bin in "${binaries[@]}"; do
    name="$(basename "$bin")"
    key="${name#dallow-}"
    printf '  %s: bin/%s\n' "$key" "$name"
  done
  echo "---"
  # body: strip the template frontmatter, keep the prose
  awk 'f{print} /^---$/{c++} c==2 && !f{f=1}' "$repo_root/tool/TOOL.md"
} > "$stage/TOOL.md"

(cd "$stage" && zip -qr "$out_zip" .)
echo "==> built $out_zip"
unzip -l "$out_zip"
