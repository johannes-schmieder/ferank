# Performance qualification

The reproducible driver is `ferank-cli bench`; `scripts/benchmark.sh` wraps it
with operating-system resource accounting and writes one immutable text log per
thread count. Synthetic graphs contain a bidirectional ring plus deterministic
weighted comparisons, so every run has one identified component.

## 2026-08-28 Mac Studio development run

Rust 1.85.1 release build on the licensed arm64 Mac Studio:

| Firms | Requested edges | Threads | Canonicalize + SCC | Sorkin | Bradley--Terry | Wall time |
|---:|---:|---:|---:|---:|---:|---:|
| 100,000 | 1,000,000 | 1 | 0.348 s | 0.989 s | 7.452 s | 8.98 s |
| 100,000 | 1,000,000 | 2 | 0.332 s | 0.542 s | 7.307 s | 8.20 s |
| 100,000 | 1,000,000 | 4 | 0.332 s | 0.394 s | 7.412 s | 8.15 s |
| 100,000 | 1,000,000 | 8 | 0.345 s | 0.321 s | 7.348 s | 8.03 s |
| 1,000,000 | 10,000,000 | 8 | 4.292 s | 5.060 s | 98.596 s | 108.34 s |

All rows ended with `FERANK_BENCH_PASS` and numerical certificates. Requested
and canonical edge counts differ slightly because deterministic random draws
can repeat a directed pair.

The sandboxed development run denied the macOS `sysctl` call used by
`/usr/bin/time -l`, so it did not produce a trustworthy peak-RSS measurement.
The benchmark wrapper retains resource output when run on the unsandboxed CI
host; peak RSS remains a release-qualification datum rather than an inferred
number. The current parallel route materially accelerates Sorkin. The
Bradley--Terry solve remains dominated by serial PCG/CMG work, so additional
threading should be retained only after numerical equivalence and
worst-case performance checks pass. See [Contributing](../CONTRIBUTING.md).
