# Contributing to ferank

The public command estimates firm rankings from directed worker flows.
Its input contract and estimands are specified in
[`docs/methods.md`](docs/methods.md). Changes to flow orientation, panel
construction, component selection, normalization or numerical acceptance
must update the help and pass the independent reference checks.

## Build and test

The Rust workspace is pinned to 1.85.1 and has no external Rust dependencies.
Install that toolchain with rustfmt and Clippy, then run:

```sh
cargo fmt --all --check
cargo clippy --locked --workspace --all-targets --all-features -- -D warnings
cargo test --locked --workspace --all-targets --all-features
python3 -m unittest discover -s ci/tests -p 'test_*.py'
```

The Mac build and licensed Stata package tests are:

```sh
bash ci/run_stata_ci.sh quick
```

This builds the universal Mac plugin, stages tracked source into a temporary
directory, isolates writable Stata ado directories, and runs numerical and
transactional package fixtures plus every clickable help example. Stage new
source files with Git before running it. Set `STATA_BIN` if the licensed
Stata executable is not at the default Mac application path.

Stata can return shell status zero after a do-file error. The authoritative
result is the explicit `stata.status` file and the required PASS markers.
Local evidence is written under the ignored `.ci/stata/run/` directory.
Licensed runs share a process lock and have a bounded timeout.

Keep tests that establish orientation, graph identification, score
normalization, numerical certification, reference agreement, determinism,
data preservation and help-example behavior. The bounded independent dense
oracles are validation code, rather than production fallback engines.

## Continuous integration

Public pushes and pull requests run Rust and Python checks on a
GitHub-hosted Linux runner. They do not require Stata or access to a
maintainer's machine.

The licensed Mac lane, including its receipt-publication step, is guarded
to run only for private-repository pushes or manual events. Pull requests
never run on that self-hosted machine. Making this repository public disables
that job; licensed qualification must then run locally or in a separate
trusted private CI repository. Do not remove those guards to test public PR code.

Private CI publishes immutable receipts at
`.ci/stata/results/<tested-sha>.json`. A qualified checkpoint requires the
exact source SHA and successful overall, Stata and Rust statuses. The
`latest.json` file is only a convenience pointer. Historical receipts are
retained as verification evidence; they do not qualify later source changes.
The tested job publishes its validated receipt directly to Git; optional
log artifacts have a seven-day retention and are not a qualification gate.
An artifact-storage quota therefore cannot prevent receipt publication.

## Benchmarks and report

[`scripts/benchmark.sh`](scripts/benchmark.sh) runs deterministic synthetic
graphs and records per-thread logs in the ignored `benchmark-results/`
directory. [`docs/benchmarks.md`](docs/benchmarks.md) states the measured
boundaries and host. Large benchmark runs are opt-in.

[`report/README.md`](report/README.md) describes the public teaching-data
application and technical report. The separate
[`bench/README_veneto.md`](bench/README_veneto.md) harness requires authorized
access to a restricted input and the separately built fereg package. That
input is not distributed here. Restricted runs never belong in GitHub CI;
their raw data and outputs remain outside Git tracking.

## Platform and distribution status

| Platform | Build entry point | Licensed Stata qualification |
|---|---|---|
| macOS Apple Silicon | `scripts/build_macos_universal.sh` | Passed |
| macOS Intel | Same universal build | Pending |
| Linux x86-64 | `scripts/build_linux_x86_64.sh` | Pending |
| Windows x86-64 | `scripts/build_windows_x86_64.ps1` | Pending |

Cross-compilation or a hosted Rust test is not licensed Stata qualification.
The source tree may be published as an alpha with these limits stated;
a packaged multi-platform release requires loadable, qualified binaries,
their checksums and corresponding source. `scripts/package_release.sh`
requires all three platform plugin artifacts and does not download them.
Peak-memory qualification remains incomplete. Do not infer a peak RSS from
timing measurements or advertise untested platforms as supported.

Keep the GPL license, copyright notices, and CMG/Stata-interface provenance
with distributed source and binaries. Third-party interface files retain
their original copyright and are not relicensed by this repository.
Before distribution, inspect the package contents and its exact binary/source
identities. No datasets, credentials, Stata license material or local
maintainer configuration belong in a source or binary release.
