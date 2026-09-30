#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIRMS="${FERANK_BENCH_FIRMS:-100000}"
EDGES="${FERANK_BENCH_EDGES:-1000000}"
METHOD="${FERANK_BENCH_METHOD:-both}"
THREAD_LIST="${FERANK_BENCH_THREADS:-1 2 4 8}"
RUSTUP_BIN="${RUSTUP_BIN:-rustup}"
TOOLCHAIN="${RUST_TOOLCHAIN:-1.85.1}"
OUTPUT_DIR="${FERANK_BENCH_OUTPUT:-$ROOT/benchmark-results}"

mkdir -p "$OUTPUT_DIR"
RUSTC_BIN="$("$RUSTUP_BIN" which --toolchain "$TOOLCHAIN" rustc)"
export PATH="$(dirname "$RUSTC_BIN"):/usr/bin:/bin:/usr/sbin:/sbin"
cd "$ROOT"
cargo build --locked --release -p ferank-cli

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
for THREADS in $THREAD_LIST; do
  LOG="$OUTPUT_DIR/benchmark-${STAMP}-f${FIRMS}-e${EDGES}-t${THREADS}.log"
  set +e
  if [[ "$(uname -s)" == "Darwin" ]]; then
    /usr/bin/time -l target/release/ferank-cli bench \
      --firms "$FIRMS" --edges "$EDGES" --threads "$THREADS" --method "$METHOD" \
      >"$LOG" 2>&1
  else
    /usr/bin/time -v target/release/ferank-cli bench \
      --firms "$FIRMS" --edges "$EDGES" --threads "$THREADS" --method "$METHOD" \
      >"$LOG" 2>&1
  fi
  BENCH_RC=$?
  set -e
  if ! grep -q '^FERANK_BENCH_PASS$' "$LOG"; then
    printf 'Benchmark failed with status %s; see %s\n' "$BENCH_RC" "$LOG" >&2
    if [[ "$BENCH_RC" -eq 0 ]]; then BENCH_RC=1; fi
    exit "$BENCH_RC"
  fi
  printf 'FERANK_BENCH_RECEIPT log=%s\n' "$LOG"
done
