#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${FERANK_VERSION:-0.1.0}"
PACKAGE_ROOT="$ROOT/dist/package/ferank-$VERSION"
ARCHIVE="$ROOT/dist/ferank-$VERSION-source-and-binaries.tar.gz"

for ARTIFACT in ferank_macos.plugin ferank_linux.plugin ferank_windows.plugin; do
  if [[ ! -f "$ROOT/dist/$ARTIFACT" ]]; then
    printf 'Missing qualified artifact: dist/%s\n' "$ARTIFACT" >&2
    exit 1
  fi
done

rm -rf "$PACKAGE_ROOT"
mkdir -p "$PACKAGE_ROOT/stata" "$PACKAGE_ROOT/source"
cp "$ROOT"/stata/*.ado "$ROOT"/stata/*.sthlp "$ROOT"/stata/ferank.pkg \
  "$ROOT"/stata/stata.toc "$PACKAGE_ROOT/stata/"
cp "$ROOT"/dist/ferank_*.plugin "$PACKAGE_ROOT/stata/"
cp "$ROOT/LICENSE" "$ROOT/NOTICE.md" "$ROOT/README.md" "$ROOT/STATUS.md" \
  "$PACKAGE_ROOT/"
cp -R "$ROOT/crates" "$ROOT/plugin" "$ROOT/vendor" "$ROOT/Cargo.toml" \
  "$ROOT/Cargo.lock" "$ROOT/rust-toolchain.toml" "$PACKAGE_ROOT/source/"

tar -C "$ROOT/dist/package" -czf "$ARCHIVE" "ferank-$VERSION"
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
else
  sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"
fi
printf 'Packaged %s\n' "$ARCHIVE"
