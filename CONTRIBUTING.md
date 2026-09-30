# Contributing to ferank

The public command estimates firm rankings from directed worker flows.
Its input contract and estimands are specified in
[`docs/methods.md`](docs/methods.md). Changes to flow orientation, panel
construction, component selection, normalization or numerical acceptance
must update the help and pass the independent reference checks.

## Build from source

The README's `net install` route includes a precompiled Mac plugin. To build
it yourself, install Git, Xcode command-line tools, and Rust through rustup:

```sh
git clone https://github.com/johannes-schmieder/ferank.git
cd ferank
rustup toolchain install 1.85.1 --profile minimal --component rustfmt --component clippy
rustup target add --toolchain 1.85.1 aarch64-apple-darwin x86_64-apple-darwin
bash scripts/build_macos_universal.sh
cp dist/ferank_macos.plugin stata/
```

Use `adopath ++ "/absolute/path/to/ferank/stata"` in Stata for your own build.
The tracked Mac binary is a distribution artifact; rebuilding it does not
by itself qualify it for publication. Refresh its checksum and repeat the
licensed package and isolated-install tests before replacing it in Git.

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
generated-variable endpoint mapping, qualifier handling, atomic output
publication, data/frame preservation and help-example behavior. The bounded independent dense
oracles are validation code, rather than production fallback engines.

## Continuous integration

Pushes and pull requests run Rust, Python and distribution-manifest checks
on a GitHub-hosted Linux runner. They do not require Stata or access to a
maintainer's machine.

Licensed Stata qualification runs locally or in a separate trusted private
CI repository. The personal Mac runner was detached before this repository
was made public. Never register it here or run public PR code on that machine.
See [GitHub's self-hosted runner security guidance](https://docs.github.com/en/actions/reference/security/secure-use).

Historical private CI published immutable receipts at
`.ci/stata/results/<tested-sha>.json`. A qualified checkpoint requires the
exact source SHA and successful overall, Stata and Rust statuses. The
`latest.json` file is only a convenience pointer. Historical receipts are
retained as verification evidence; they do not qualify later source changes.
Keep those records as historical evidence. Current local runs write evidence
under the ignored `.ci/stata/run/` directory.

The installer can be tested without changing the user's normal ado directory:

```sh
python3 ci/test_stata_install.py --output /tmp/ferank-install-test
```

It runs the exact README install block and both examples in a fresh licensed
Stata process, then executes all five help examples. To test a staged local
package, pass `--source /absolute/path/to/package`; the default source is the
public GitHub URL. The output directory must not already exist.

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
