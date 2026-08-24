# Licensed Stata/Rust CI runner

`texpdf` uses one private, repository-level GitHub Actions runner on the Mac
Studio. Workflow code executes as the logged-in `johannes` macOS account and
therefore has the same practical authority as that account.

## Machine and tools

- Mac Studio `Mac14,14`, Apple M2 Ultra, arm64, 24 CPU cores, 192 GB RAM.
- macOS 26.5.2 build 25F84.
- Stata/MP 18 bundle 18.0.130, executable
  `/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp`.
- Batch invocation: `stata-mp -q -b do FILE.do`.
- Rust stable 1.97.1 with rustfmt and Clippy; installed pinned toolchains also
  include 1.81.0 and 1.85.1.
- Apple clang/Xcode and TeX Live 2023 are installed.

Stata can return shell status zero after a Stata-language error. CI therefore
requires an explicit `stata.status` file and a profile-specific PASS marker.
Launch errors, timeouts, crashes, missing outputs, Stata errors, and Rust
errors are distinct receipt failures.

## Repository interface

The workflow is `.github/workflows/stata-ci.yml`. Pushes to `main` and
`codex/**` run the `quick` Stata/Mata infrastructure smoke plus Rust quick
checks. Manual profiles are `version`, `smoke`, and `quick`. There is no
`pull_request` trigger and no hosted matrix.

Run locally from repository root with:

```sh
./ci/run_stata_ci.sh version
./ci/run_stata_ci.sh smoke
./ci/run_stata_ci.sh quick
./ci/run_rust_quick.sh
```

Each Stata run stages only Git-tracked files into a fresh temporary tree,
isolates all writable Stata system directories, and uses the shared lock
`/private/tmp/varcomp-kss-stata-ci.lock`. A timeout terminates only the test
process group. Sanitized evidence is copied to `.ci/stata/run/`; the raw Stata
startup stream is not uploaded.

The publisher commits immutable
`.ci/stata/results/<tested-sha>.json` receipts and updates
`.ci/stata/latest.json` only when the tested SHA remains the newest source
change. Receipt paths are excluded from triggers and commits use `[skip ci]`.

## Runner installation and operation

- Installation: `/Users/johannes/actions-runners/texpdf-stata`.
- Runner name: `macstudio-stata-mp18-texpdf`.
- Scope: private `johannes-schmieder/texpdf` repository only.
- Labels: `self-hosted`, `macOS`, `ARM64`, `stata`, `stata-mp`, `stata18`,
  `texpdf`.
- Work directory: `_work` under the installation.
- LaunchAgent:
  `/Users/johannes/Library/LaunchAgents/actions.runner.johannes-schmieder-texpdf.macstudio-stata-mp18-texpdf.plist`.

Manage the service from the installation directory with `./svc.sh status`,
`./svc.sh stop`, and `./svc.sh start`. The user must remain logged into the
GUI session. AC system sleep is disabled; display sleep is harmless. The
runner makes outbound GitHub connections only and opens no inbound port.

The authoritative service check is:

```sh
launchctl print \
  "gui/$(id -u)/actions.runner.johannes-schmieder-texpdf.macstudio-stata-mp18-texpdf"
```

For an offline or stuck runner, inspect **Settings → Actions → Runners** and
the bounded LaunchAgent stdout/stderr logs under
`/Users/johannes/Library/Logs/actions.runner.johannes-schmieder-texpdf.macstudio-stata-mp18-texpdf/`.

To unregister, stop and uninstall the service, remove the runner in repository
settings or use a fresh short-lived removal token, and then delete the
installation only after confirming registration is gone. Re-registration uses
a new short-lived repository token and the recorded name, labels, and work
directory. Never store a token in this file or Git.

## Security assumptions

- The repository remains private and workflow writers are trusted.
- Fork and pull-request execution remain disabled.
- Artifacts are restricted to `.ci/stata/run/` and synthetic fixtures.
- Home-directory content, credentials, license material, and confidential
  research data are never uploaded.
- Package API, TeX backend, and platform support are intentionally undecided.

## Qualification record

The bootstrap, deliberate-failure, restored-green, merge, and final-main run
identifiers are recorded here after end-to-end qualification.
