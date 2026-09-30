#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
profile="${1:-quick}"
repo_root="$(cd "$script_dir/.." && pwd)"
if [[ "$profile" != "quick" ]]; then
  printf 'Only the quick package profile is supported\n' >&2
  exit 2
fi
"$repo_root/scripts/build_macos_universal.sh"
exec /usr/bin/python3 "$script_dir/run_stata_ci.py" "$profile"
