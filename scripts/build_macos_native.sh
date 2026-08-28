#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/target/native-macos"
DIST="$ROOT/dist"
RUSTUP_BIN="${RUSTUP_BIN:-/opt/homebrew/bin/rustup}"
TOOLCHAIN="${RUST_TOOLCHAIN:-1.85.1}"

mkdir -p "$BUILD" "$DIST"
RUSTC_BIN="$($RUSTUP_BIN which --toolchain "$TOOLCHAIN" rustc)"
TOOLCHAIN_BIN="$(dirname "$RUSTC_BIN")"
export PATH="$TOOLCHAIN_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

cargo build --locked --release -p ferank-plugin

COMMON_CFLAGS=(
  -std=c11 -O3 -fPIC -Wall -Wextra -Wpedantic -Wconversion -Wshadow
  -Wstrict-prototypes -Wmissing-prototypes -Werror
  -DSYSTEM=APPLEMAC -I"$ROOT/plugin"
)
clang "${COMMON_CFLAGS[@]}" -c "$ROOT/plugin/stplugin.c" -o "$BUILD/stplugin.o"
clang "${COMMON_CFLAGS[@]}" -c "$ROOT/plugin/stata_bridge.c" -o "$BUILD/stata_bridge.o"
clang -bundle -Wl,-dead_strip \
  -Wl,-exported_symbols_list,"$ROOT/plugin/exports_macos.txt" \
  "$BUILD/stplugin.o" "$BUILD/stata_bridge.o" \
  "$ROOT/target/release/libferank_plugin.a" \
  -framework Security -framework CoreFoundation -framework SystemConfiguration \
  -liconv -lresolv -lpthread \
  -o "$DIST/ferank_macos.plugin"

codesign --force --sign - "$DIST/ferank_macos.plugin"
shasum -a 256 "$DIST/ferank_macos.plugin" > "$DIST/ferank_macos.plugin.sha256"
printf 'Built %s\n' "$DIST/ferank_macos.plugin"
