#!/bin/bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
rustup_bin="${RUSTUP_BIN:-$(command -v rustup || true)}"

if [[ ! -x "$rustup_bin" ]]; then
  echo "Rust quick check could not find rustup at $rustup_bin" >&2
  exit 127
fi

cd "$repo_root"
if [[ -n "${RUST_TOOLCHAIN:-}" ]]; then
  toolchain="$RUST_TOOLCHAIN"
else
  active_toolchain="$($rustup_bin show active-toolchain)"
  toolchain="${active_toolchain%% *}"
fi

if ! "$rustup_bin" toolchain list | /usr/bin/grep -Eq "^${toolchain}([[:space:]]|$)"; then
  echo "Required Rust toolchain $toolchain is not installed" >&2
  exit 127
fi

rustc_bin="$($rustup_bin which --toolchain "$toolchain" rustc)"
toolchain_bin="$(dirname "$rustc_bin")"
export PATH="$toolchain_bin:/usr/bin:/bin:/usr/sbin:/sbin"
rustc_version="$(rustc --version)"
echo "RUST_TOOLCHAIN=$toolchain"
echo "RUSTC_VERSION=$rustc_version"

cargo fmt --all --check
cargo clippy --locked --workspace --all-targets --all-features -- -D warnings
cargo test --locked --workspace --all-targets --all-features
echo "RUST_QUICK_MODE=repository"
