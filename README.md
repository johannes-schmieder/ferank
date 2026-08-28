# ferank

`ferank` is a Stata 18 package for firm rankings constructed from directed
worker flows. Version 0.1 implements two point estimators over one canonical
flow graph:

- the Sorkin revealed-preference fixed point; and
- a Bradley--Terry likelihood in which the destination firm wins each observed
  origin-to-destination comparison.

Both methods accept prepared directed edges or a narrow worker--firm period
panel. Successful estimates create a firm-level Stata frame with normalized
scores, deterministic midranks, percentiles, graph coverage, and explicit
numerical certificates. The caller's data are not modified.

## Examples

Prepared edges:

```stata
ferank origin destination, method(sorkin) flow(moves) ///
    frame(sorkin_ranking) replace

ferank origin destination, method(bradleyterry) flow(moves) ///
    frame(bt_ranking) replace
```

Worker-period panel:

```stata
ferank firm, worker(worker_id) time(year) method(sorkin) ///
    maxgap(1) frame(firm_ranking) replace
```

Inspect the certificate with `estat convergence` and component coverage with
`estat components`.

## Scientific boundary

Version 0.1 returns point rankings from worker flows. It does not estimate wage
fixed effects, structural employer values, offer shares, rents, amenities,
standard errors, bootstrap intervals, or influence functions. It never joins
components or adds hidden smoothing, teleportation, or ridge terms.

The exact input contract and numerical methods are documented in
[`docs/methods.md`](docs/methods.md). [`PLAN.md`](PLAN.md) is the authoritative
development and qualification roadmap.

## Development

The dependency-free Rust workspace is pinned to Rust 1.85.1:

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-targets --all-features
```

On the licensed Mac development host:

```sh
scripts/build_macos_native.sh
ci/run_stata_ci.sh quick
```

The deterministic performance driver accepts explicit graph and thread sizes:

```sh
FERANK_BENCH_THREADS="1 2 4 8" scripts/benchmark.sh
```

The current qualification record is in
[`docs/benchmarks.md`](docs/benchmarks.md).

Platform artifact entrypoints are `scripts/build_macos_universal.sh`,
`scripts/build_linux_x86_64.sh`, and `scripts/build_windows_x86_64.ps1`.
`windows-ci.do` is the bounded licensed-Windows driver. A platform is not
advertised merely because it cross-compiles; it must load and pass the Stata
fixtures on that platform.

Every accepted checkpoint requires an immutable receipt under
`.ci/stata/results/<tested-sha>.json` whose exact source SHA and Stata/Rust
statuses are successful. `latest.json` is only a pointer.

## License

The package is licensed under GPL-3.0-only. See [`LICENSE`](LICENSE),
[`NOTICE.md`](NOTICE.md), and the CMG provenance record under `vendor/cmg/`.
