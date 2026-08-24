#!/bin/bash
set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git rev-parse --show-toplevel)"
run_dir="$repo_root/.ci/stata/run"
log_file="$run_dir/rust-quick.log"
status_file="$run_dir/rust-quick.status"
/bin/mkdir -p "$run_dir"

"$script_dir/run_rust_quick.sh" >"$log_file" 2>&1
rust_rc=$?
/bin/cat "$log_file"

if [[ $rust_rc -eq 0 ]]; then
  rust_status=success
else
  rust_status=failure
fi
rust_mode="$(/usr/bin/sed -n 's/^RUST_QUICK_MODE=//p' "$log_file" | /usr/bin/tail -n 1)"
rust_toolchain="$(/usr/bin/sed -n 's/^RUST_TOOLCHAIN=//p' "$log_file" | /usr/bin/tail -n 1)"
rustc_version="$(/usr/bin/sed -n 's/^RUSTC_VERSION=//p' "$log_file" | /usr/bin/tail -n 1)"

/usr/bin/printf 'schema_version=1\nrust_status=%s\nrust_rc=%s\nrust_mode=%s\nrust_toolchain=%s\nrustc_version=%s\ncompleted=1\n' \
  "$rust_status" "$rust_rc" "$rust_mode" "$rust_toolchain" "$rustc_version" >"$status_file"
exit "$rust_rc"
