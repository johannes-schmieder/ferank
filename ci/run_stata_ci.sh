#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
profile="${1:-quick}"
repo_root="$(cd "$script_dir/.." && pwd)"
if [[ "$profile" == "quick" && -f "$repo_root/Cargo.toml" ]]; then
  "$repo_root/scripts/build_macos_universal.sh"
fi
exec /usr/bin/python3 "$script_dir/run_stata_ci.py" "$profile"
