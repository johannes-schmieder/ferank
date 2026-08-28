#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/target/native-linux-x86_64"
DIST="$ROOT/dist"
RUSTUP_BIN="${RUSTUP_BIN:-rustup}"
TOOLCHAIN="${RUST_TOOLCHAIN:-1.85.1}"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  printf 'This builder requires a Linux x86_64 host\n' >&2
  exit 126
fi
mkdir -p "$BUILD" "$DIST"
RUSTC_BIN="$($RUSTUP_BIN which --toolchain "$TOOLCHAIN" rustc)"
export PATH="$(dirname "$RUSTC_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
cd "$ROOT"
cargo build --locked --release -p ferank-plugin

COMMON_CFLAGS=(
  -std=c11 -O3 -fPIC -Wall -Wextra -Wpedantic -Wconversion -Wshadow
  -Wstrict-prototypes -Wmissing-prototypes -Werror
  -fvisibility=hidden -DSYSTEM=OPUNIX -I"$ROOT/plugin"
)
cc "${COMMON_CFLAGS[@]}" -c "$ROOT/plugin/stplugin.c" -o "$BUILD/stplugin.o"
cc "${COMMON_CFLAGS[@]}" -c "$ROOT/plugin/stata_bridge.c" -o "$BUILD/stata_bridge.o"
cc -shared -Wl,--no-undefined -Wl,--version-script,"$ROOT/plugin/exports_linux.map" \
  "$BUILD/stplugin.o" "$BUILD/stata_bridge.o" \
  "$ROOT/target/release/libferank_plugin.a" -ldl -lpthread -lm \
  -o "$DIST/ferank_linux.plugin"
sha256sum "$DIST/ferank_linux.plugin" > "$DIST/ferank_linux.plugin.sha256"
printf 'Built %s\n' "$DIST/ferank_linux.plugin"
