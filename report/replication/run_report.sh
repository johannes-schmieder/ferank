#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT="$ROOT/report"
STATA_BIN="${STATA_BIN:-/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp}"
PYTHON_BIN="${FERANK_REPORT_PYTHON:-/Users/johannes/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3}"
VENETO_SOURCE="${FERANK_VENETO_SOURCE:-}"

mkdir -p "$REPORT/output" "$REPORT/build" "$REPORT/data/external"
if [[ -n "$VENETO_SOURCE" ]]; then
  "$PYTHON_BIN" "$REPORT/replication/stage_veneto_example.py" --source "$VENETO_SOURCE"
else
  "$PYTHON_BIN" "$REPORT/replication/stage_veneto_example.py"
fi

"$ROOT/scripts/build_macos_native.sh"
cp "$ROOT/dist/ferank_macos.plugin" "$ROOT/stata/ferank_macos.plugin"
"$STATA_BIN" -q -b do "$REPORT/replication/run_veneto.do" \
  "$ROOT" "$REPORT/data/external/kss_example_1999_2001.csv" "$REPORT/output" \
  "$REPORT/replication/run_veneto.log"
if ! grep -q "FERANK VENETO REPORT PASS" "$REPORT/replication/run_veneto.log"; then
  printf 'The Veneto Stata run did not emit its PASS marker\n' >&2
  exit 1
fi

"$PYTHON_BIN" "$REPORT/replication/generate_exhibits.py" \
  --data "$REPORT/data/external/kss_example_1999_2001.csv" \
  --results "$REPORT/output" --generated "$REPORT/generated"

cd "$REPORT"
latexmk -pdf -interaction=nonstopmode -halt-on-error -outdir=build ferank_technical_report.tex
cp build/ferank_technical_report.pdf output/ferank_technical_report.pdf
printf 'Built %s\n' "$REPORT/output/ferank_technical_report.pdf"
