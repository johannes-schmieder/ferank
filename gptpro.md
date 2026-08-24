# GPT Pro handoff: licensed Stata and Rust CI

This private repository uses a repository-scoped GitHub Actions runner on Johannes's Mac Studio. Use it when a ChatGPT/GPT Pro session cannot execute licensed Stata or Rust in its own sandbox.

## What this repository provides

The workflow is named **Licensed Stata and Rust CI**. A normal push to `main` or a trusted `codex/**` branch runs one nonredundant macOS lane:

1. a licensed Stata/MP batch test; and
2. a Rust quick test.

At bootstrap, the Stata test is an infrastructure smoke test and the Rust test compiles and runs a synthetic program in a temporary directory. No `texpdf` package API or TeX compiler backend has been chosen yet. When a `Cargo.toml` is later added, the Rust lane automatically changes to repository checks: `cargo fmt --check`, strict Clippy, and workspace tests.

There is no self-hosted `pull_request` trigger and no redundant GitHub-hosted matrix on ordinary pushes.

## Available test machine

- Runner: `macstudio-stata-mp18-texpdf`
- Labels: `self-hosted`, `macOS`, `ARM64`, `stata`, `stata-mp`, `stata18`, `texpdf`
- Hardware: Mac Studio `Mac14,14`, Apple M2 Ultra, arm64, 24 CPU cores, 192 GB RAM
- Operating system: macOS 26.5.2
- Licensed Stata: Stata/MP 18, bundle 18.0.130
- Stata executable: `/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp`
- Working Stata batch form: `stata-mp -q -b do FILE.do`
- Rust: stable 1.97.1, plus installed 1.81.0 and 1.85.1 toolchains; rustfmt and Clippy are available
- Native build tools: Apple clang/Xcode
- TeX tools currently present on the Mac: TeX Live 2023, `latexmk`, pdfLaTeX, XeLaTeX, LuaLaTeX, BibTeX, and Biber

Treat those versions as the current runner environment, not as a future public package compatibility promise. A repository `rust-toolchain.toml` may pin Rust when development begins.

## Development loop

1. Read this file, `STATA_CI_RUNNER.md`, the workflow, and the current branch state.
2. Create or use a trusted `codex/**` branch.
3. Make a focused change, record the exact full source commit SHA, and push it using the write-capable GitHub/Codex tools available in the session.
4. Query workflow runs for that exact commit when the connector exposes commit-bound workflow discovery. Otherwise wait for the immutable receipt below.
5. Read `.ci/stata/results/<full-source-sha>.json`. Do not infer success from the branch head or from an older receipt.
6. Require all of:
   - `tested_sha` exactly equals the intended source commit;
   - `status` is `success`;
   - `stata_status` is `success`;
   - `rust_status` is `success`;
   - `profile` is the intended profile.
7. Use `.ci/stata/latest.json` only as a convenience pointer and always verify its complete `tested_sha`. Receipt publisher commits advance the branch after the source push and use `[skip ci]`.
8. On failure, inspect `failure_kind`, `process_rc`, `stata_rc`, `rust_rc`, the workflow jobs, and the artifact named for the source SHA/run. Fix the source, push a new checkpoint, and repeat.
9. Merge only an exact-SHA green checkpoint. Never merge a deliberate failing checkpoint into `main`.

Manual workflow profiles are `version`, `smoke`, and `quick`. Normal pushes use `quick`. More profiles can be added in repository configuration when actual Stata/Mata or plugin tests exist; no machine-level runner changes should be needed.

## Important failure semantics

Stata on this Mac can return shell status zero even after a Stata-language error. The workflow therefore treats the explicit Stata status file and PASS marker as authoritative. It separately distinguishes launch failure, timeout, crash or missing output, ordinary Stata error, and Rust failure.

A missing exact-SHA receipt is not evidence that the source passed or failed. It means the run may be queued, the runner may be offline or busy, the run may have been cancelled, or the publisher may have failed. Inspect the exact commit's workflow run or ask the owner to check **Settings → Actions → Runners**.

## GitHub access note

OpenAI's standard ChatGPT GitHub app may be read-only in some ChatGPT experiences. If the current GPT Pro session lacks branch/file write actions, it cannot push a checkpoint by itself; use a write-capable Codex session or another authorized Git client for the push, then use the same receipt loop. Newly created private repositories may also need to be enabled under **Settings → Apps → GitHub → Choose repositories** and can take several minutes to appear.

## Security boundary

The self-hosted runner executes workflow code with the authority of the logged-in macOS user. Therefore:

- use only this private repository and trusted branches;
- never enable execution for public repositories, public pull requests, or untrusted forks;
- never print, request, commit, or upload registration tokens, passwords, credentials, Stata license material, home-directory contents, unrelated files, or confidential research data;
- use synthetic fixtures unless the owner explicitly authorizes data;
- keep artifacts limited to `.ci/stata/run/`;
- do not change machine-level runner configuration from repository code;
- do not claim Stata or Rust ran locally inside the ChatGPT sandbox.

Lead every CI report with the exact tested SHA, profile, overall status, Stata status, Rust status, and any qualification boundary.
