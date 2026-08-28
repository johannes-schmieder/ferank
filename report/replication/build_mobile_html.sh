#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT="$ROOT/report"
OUTPUT="${1:-$REPORT/output/ferank_technical_report_mobile.html}"
MAKE4HT_BIN="${MAKE4HT_BIN:-$(command -v make4ht || true)}"
BIBTEX_BIN="${BIBTEX_BIN:-$(command -v bibtex || true)}"
PDFTOPPM_BIN="${PDFTOPPM_BIN:-$(command -v pdftoppm || true)}"
PYTHON_BIN="${FERANK_REPORT_PYTHON:-$(command -v python3 || true)}"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/ferank-mobile-html.XXXXXX")"

for tool in "$MAKE4HT_BIN" "$BIBTEX_BIN" "$PDFTOPPM_BIN" "$PYTHON_BIN"; do
  if [[ -z "$tool" || ! -x "$tool" ]]; then
    printf 'Required executable not found: %s\n' "${tool:-unset}" >&2
    exit 1
  fi
done

mkdir -p "$WORK/generated" "$(dirname "$OUTPUT")"
cp "$REPORT/ferank_technical_report.tex" "$REPORT/references.bib" "$WORK/"
cp "$REPORT"/generated/*.tex "$REPORT"/generated/*.pdf "$WORK/generated/"

cd "$WORK"
"$MAKE4HT_BIN" -u ferank_technical_report.tex "html5,mathml"
"$BIBTEX_BIN" ferank_technical_report
"$MAKE4HT_BIN" -u ferank_technical_report.tex "html5,mathml"

for figure in graph_concepts veneto_network rank_comparison akm_comparison; do
  "$PDFTOPPM_BIN" -f 1 -l 1 -png -r 220 -singlefile \
    "$WORK/generated/${figure}.pdf" "$WORK/generated/${figure}-" >/dev/null 2>&1
done

"$PYTHON_BIN" "$REPORT/replication/package_mobile_html.py" \
  --html "$WORK/ferank_technical_report.html" \
  --css "$WORK/ferank_technical_report.css" \
  --output "$OUTPUT"

printf 'Built %s\n' "$OUTPUT"
