# ferank

**Rank firms from the jobs workers move between, in Stata.**

`ferank` estimates Sorkin and Bradley–Terry firm rankings from observed
worker moves. Give it either a worker-period panel or a table of moves from
origin to destination firms. It returns firm scores, ranks and percentiles
in a separate Stata frame, leaving your data unchanged.

The methods describe revealed preference in worker flows. They can be compared
with wage effects estimated separately, but they do not estimate wages,
amenities or a compensating-wage decomposition. Higher scores mean better
ranked firms: **rank 1 is best**, and percentile 100 is highest.

Version 0.1.0 is **alpha software**, currently available as source.
It requires Stata 18 or later.
The compiled plugin has passed licensed Stata tests on Apple Silicon Macs.
The Mac build also contains an Intel slice; licensed Intel Mac, Linux and
Windows qualification is still pending. There is no SSC installation or
prebuilt release download yet.

## Install from source on a Mac

You need Git, [Rust installed through rustup](https://rustup.rs/), and Xcode's
command-line tools. In Terminal:

```sh
git clone https://github.com/johannes-schmieder/ferank.git
cd ferank
rustup toolchain install 1.85.1 --profile minimal --component rustfmt --component clippy
rustup target add --toolchain 1.85.1 aarch64-apple-darwin x86_64-apple-darwin
bash scripts/build_macos_universal.sh
cp dist/ferank_macos.plugin stata/
```

In Stata, replace the path below with the absolute path to your clone's
`stata` folder. Add this line to your do-file so the command is available
in later sessions:

```stata
adopath ++ "/path/to/ferank/stata"
ferank, selftest
help ferank
```

The selftest checks that Stata can load and call the plugin. The ado files,
help files and plugin must come from the same source version.

## Try a complete example

Run the prepared-flow example embedded in the help file:

```stata
ferank_run edges using ferank.sthlp
```

It creates six directed flows among three firms, estimates Sorkin scores,
prints the convergence diagnostics and lists the rankings. Your existing
data are restored and the temporary result frame is removed afterward.
The help file has four further clickable examples, including a worker-year
panel and a comparison of both methods.

## Use your own data

### A worker-year panel

Suppose each row identifies one worker's employer in one year:

```stata
ferank firm_id, worker(worker_id) time(year) method(sorkin) ///
    frame(firm_ranking)
```

Each worker-year must have a single employer assignment. A move is formed
when consecutive observations have different employers and are at most one
time unit apart, the default `maxgap(1)`. A missing employer breaks the
chain. Same-firm continuations add no move. Time must be numeric; its units
determine the meaning of `maxgap()`.

The command's annual-panel rule cannot identify intervening unemployment or
concurrent jobs. Resolve those cases before estimation, or construct a move
table using your own spell and employer-to-employer transition rules.

### A prepared move table

Use `origin` for the employer a worker leaves and `destination` for the
employer they join. If `moves` contains a count or positive fractional flow:

```stata
ferank origin destination, method(bradleyterry) flow(moves) ///
    frame(bt_ranking)
```

Without `flow()`, each row represents one move. Duplicate directed pairs
are aggregated. Zero flows and self-moves contribute no comparison;
missing IDs or missing/negative flows are errors. Numeric and string firm
IDs are supported. Both methods can use either input format.

## Read the results

Immediately after the worker-panel command above:

```stata
estat convergence
estat components
frame firm_ranking: sort rank
frame firm_ranking: list firm_id score rank percentile if rank<=10
```

The result frame contains the original firm ID, method, component, score,
rank, percentile, and flow totals. The default normalization sets the mean
score to zero. This only changes the score's origin; it leaves the rankings
unchanged. `estat convergence` reports computational accuracy, not a
sampling standard error. Version 0.1 provides point estimates without
statistical inference.

Scores are estimated within a **strongly connected component**: a group
where moves provide a directed path from every firm to every other firm.
The default selects the largest such group. Firms outside it receive no
score, so check coverage before interpreting the rankings. If you request
`component(all)`, each group's scores and ranks are separate; they cannot
be compared across groups.

Sorkin uses the stationary flow system, adjusting stationary mass by firm
outflow. Bradley–Terry models the destination as winning a pairwise
comparison against the origin. The scores have different interpretations
and the methods can produce different rankings. For comparisons with AKM
effects, match the same firms and choose comparison weights explicitly.
`normweight()` only centers scores; it does not weight ranks or correlations.

An existing result frame is protected. Use a new `frame()` name to keep
another ranking, or specify `replace` to replace that frame after success.

## Learn more

- [`help ferank`](stata/ferank.sthlp): options, examples, sample rules and all
  stored results, best viewed in Stata.
- [Postestimation help](stata/ferank_postestimation.sthlp): graph coverage and
  numerical certificates.
- [Methods](docs/methods.md): equations and the precise flow-input contract.
- [Technical companion](report/README.md): a longer explanation and a
  reproducible application using a public Veneto teaching extract.
- [Benchmarks](docs/benchmarks.md): synthetic performance results and their
  timing boundaries.
- [Contributing](CONTRIBUTING.md): builds, tests, CI and release qualification.

For a bug report, include the command, Stata version, error message and a
small reproducible example using synthetic or shareable data. Please do not
attach confidential worker or firm records.

## References and license

Sorkin, Isaac. 2018. “Ranking Firms Using Revealed Preference.”
*Quarterly Journal of Economics* 133(3): 1331–1393.
[doi:10.1093/qje/qjy001](https://doi.org/10.1093/qje/qjy001).

Bradley, Ralph Allan, and Milton E. Terry. 1952. “Rank Analysis of Incomplete
Block Designs: I. The Method of Paired Comparisons.” *Biometrika*
39(3–4): 324–345.
[doi:10.1093/biomet/39.3-4.324](https://doi.org/10.1093/biomet/39.3-4.324).

Author: Johannes F. Schmieder, Boston University.
Repository-authored code and the CMG adaptation are GPL-3.0-only. See
[`LICENSE`](LICENSE), [`NOTICE.md`](NOTICE.md) and the recorded third-party
provenance for the Stata plugin interface and CMG source.
