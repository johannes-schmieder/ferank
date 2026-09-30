#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/target/native-macos-universal"
DIST="$ROOT/dist"
RUSTUP_BIN="$(command -v "${RUSTUP_BIN:-rustup}")"
TOOLCHAIN="${RUST_TOOLCHAIN:-1.85.1}"
TARGETS=(aarch64-apple-darwin x86_64-apple-darwin)

mkdir -p "$BUILD" "$DIST"
RUSTC_BIN="$("$RUSTUP_BIN" which --toolchain "$TOOLCHAIN" rustc)"
export PATH="$(dirname "$RUSTC_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
cd "$ROOT"

for TARGET in "${TARGETS[@]}"; do
  if ! "$RUSTUP_BIN" target list --toolchain "$TOOLCHAIN" --installed | grep -qx "$TARGET"; then
    printf 'Missing Rust target %s for toolchain %s\n' "$TARGET" "$TOOLCHAIN" >&2
    exit 127
  fi
  case "$TARGET" in
    aarch64-apple-darwin) ARCH=arm64 ;;
    x86_64-apple-darwin) ARCH=x86_64 ;;
  esac
  TARGET_BUILD="$BUILD/$ARCH"
  mkdir -p "$TARGET_BUILD"
  cargo build --locked --release -p ferank-plugin --target "$TARGET"
  COMMON_CFLAGS=(
    -std=c11 -O3 -fPIC -Wall -Wextra -Wpedantic -Wconversion -Wshadow
    -Wstrict-prototypes -Wmissing-prototypes -Werror
    -arch "$ARCH" -DSYSTEM=APPLEMAC -I"$ROOT/plugin"
  )
  clang "${COMMON_CFLAGS[@]}" -c "$ROOT/plugin/stplugin.c" -o "$TARGET_BUILD/stplugin.o"
  clang "${COMMON_CFLAGS[@]}" -c "$ROOT/plugin/stata_bridge.c" -o "$TARGET_BUILD/stata_bridge.o"
  clang -arch "$ARCH" -bundle -Wl,-dead_strip \
    -Wl,-exported_symbols_list,"$ROOT/plugin/exports_macos.txt" \
    "$TARGET_BUILD/stplugin.o" "$TARGET_BUILD/stata_bridge.o" \
    "$ROOT/target/$TARGET/release/libferank_plugin.a" \
    -framework Security -framework CoreFoundation -framework SystemConfiguration \
    -liconv -lresolv -lpthread -o "$TARGET_BUILD/ferank_macos.plugin"
done

lipo -create \
  "$BUILD/arm64/ferank_macos.plugin" \
  "$BUILD/x86_64/ferank_macos.plugin" \
  -output "$DIST/ferank_macos.plugin"
codesign --force --sign - "$DIST/ferank_macos.plugin"
shasum -a 256 "$DIST/ferank_macos.plugin" > "$DIST/ferank_macos.plugin.sha256"
lipo -archs "$DIST/ferank_macos.plugin"
printf 'Built %s\n' "$DIST/ferank_macos.plugin"
