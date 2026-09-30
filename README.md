# ferank

`ferank` ranks firms from the jobs workers move between. It estimates firm
scores, ranks and percentiles in Stata from either a worker–employer panel
or a table of employer-to-employer moves.

Two methods are available:

- **Sorkin:** a flow-based revealed-preference ranking following
  [Sorkin (2018)](https://doi.org/10.1093/qje/qjy001). It uses the full network
  of moves and adjusts stationary mass by each firm's total outflow.
- **Bradley–Terry:** a paired-comparison ranking following
  [Bradley and Terry (1952)](https://doi.org/10.1093/biomet/39.3-4.324).
  A move from firm A to firm B counts as a win for B over A.

Higher scores mean better-ranked firms. Rank 1 is best; exact ties receive
average ranks. Request new variables with `generate()` for ranks, `score()` for continuous
scores and `percentile()` for equal-firm percentiles. The command adds only
those variables, preserving existing data and observation order. These are point estimates from the supplied flows.
Interpreting them as worker preferences requires an appropriate transition
sample and assumptions about workers' opportunities. The command does not
estimate wage effects, amenities or Sorkin's compensating-differential
and structural-adjustment calculations.

## Requirements

- Stata 18 or later on macOS.
- A precompiled universal Mac plugin is included: **no Rust installation,
  compiler or other Stata package is needed**.
- Licensed Stata/MP 19 tests have passed on Apple Silicon. The plugin also
  contains an Intel Mac build, whose licensed runtime qualification is pending.

This is version 0.1.0, an **alpha package**. Linux and Windows binaries are
not included in this installation; their licensed Stata qualification is
pending. See [Contributing](CONTRIBUTING.md) for source builds and testing.

## Installation

Install directly from GitHub in Stata, using the same `net install` route
as the other packages in this account:

```stata
net install ferank, replace ///
    from("https://raw.githubusercontent.com/johannes-schmieder/ferank/main/")
ferank, selftest
help ferank
```

This installs the command, help files and compiled Mac plugin into Stata's
ado directory. No manual download or `adopath` change is required. The
selftest checks that the plugin loads and runs. For updates, restart Stata
before running the installation command again, so a previously loaded plugin
is replaced in memory. This GitHub install follows `main`; ferank is not on SSC.

## Example 1: Rank firms from a worker-year panel

The following complete example creates a small panel and estimates Sorkin
scores. Each worker-year has one employer. The six workers generate moves
among three firms. Copy the whole block into Stata:

```stata
preserve
clear
input long worker int year long firm
1 2000 1
1 2001 2
2 2000 1
2 2001 2
3 2000 2
3 2001 3
4 2000 3
4 2001 1
5 2000 2
5 2001 1
6 2000 3
6 2001 2
end

ferank firm, worker(worker) time(year) method(sorkin) ///
    generate(sorkin_rank) score(sorkin_score) percentile(sorkin_pct)
estat convergence
list worker year firm sorkin_rank sorkin_score sorkin_pct, noobs sepby(worker)
restore
```

With your own panel, substitute your employer, worker and time variables.
Each selected row receives its employer's estimated values, including rows
for workers who never move when their employer is ranked. A move is formed
between consecutive observations when the employer changes
and the gap is at most `maxgap(1)`, the default. Missing employers break the
chain. Construct your own move table when spells, concurrent jobs or
intervening unemployment require different transition rules.

## Example 2: Rank firms from a table of moves

Here each row records an origin, a destination and the number of moves
between them. For example, four workers move from firm 1 to firm 2, and one
moves in the opposite direction. Estimate Bradley–Terry scores:

```stata
preserve
clear
input double(origin destination moves)
1 2 4
2 1 1
2 3 3
3 2 1
3 1 2
1 3 1
end

ferank origin destination, method(bradleyterry) flow(moves) ///
    generate(origin_rank destination_rank) ///
    score(origin_score destination_score)
estat convergence
list origin destination moves origin_rank destination_rank, noobs
restore
```

Every requested output option takes **one new variable in panel mode** and
**two in flow-table mode, origin first and destination second**. At least one
of `generate()`, `score()` or `percentile()` is required; requesting only
`score()` is useful when comparing continuous scores with AKM effects.

Both methods accept either input format. Use `method(sorkin)` on the same
move table to compare rankings. Without `flow()`, each row represents one
move; duplicate pairs are aggregated. Positive fractional flows are allowed.

## Reading and checking a ranking

Scores are comparable within a **strongly connected component**: a group
where directed moves provide a path from every firm to every other firm.
The default selects the largest such group. Use `estat components` to check
coverage. With `component(all)`, each group's scores and ranks are separate.
Save their group labels with `componentid(firm_component)` in panel mode or
`componentid(origin_component destination_component)` with prepared flows.

The default normalization centers scores at zero. It leaves ranks unchanged.
Percentiles run from 0 to 100, with higher values indicating better ranks.
`estat convergence` checks numerical accuracy; it does not provide sampling
standard errors.

`if` and `in` select rows both for constructing flows and for filling the new
variables. Other rows remain missing, even if their employers are ranked.
Selected rows whose employers are outside the estimated components also have
missing values. In flow tables, each endpoint is matched independently.

Ranks start at 1 for the best firm; tied firms receive their average rank.
Percentiles use equal firm weights even when scores use weighted centering.
Repeating scores across a panel means a correlation on worker-year rows
weights firms by their matched person-years. Keep one row per firm for an
equal-firm comparison.

Output variable names must be new and distinct. Failed estimation creates no
partial outputs. No result frame is created, and the former `frame()` and
`replace` options are no longer supported; update older do-files to request
named variables. Retain distinct names when comparing methods.

## Documentation and support

- [`help ferank`](stata/ferank.sthlp): syntax, options, five clickable examples,
  input rules and stored results.
- [Postestimation help](stata/ferank_postestimation.sthlp): components and
  convergence diagnostics.
- [Methods](docs/methods.md): equations and precise sample rules.
- [Technical companion](report/README.md): an explanation and reproducible
  application using a public Veneto teaching extract.
- [Benchmarks](docs/benchmarks.md) and [Contributing](CONTRIBUTING.md).

Report bugs through [GitHub issues](https://github.com/johannes-schmieder/ferank/issues).
Include your command, Stata version, error message and a small reproducible
example using synthetic or shareable data.

## References

Sorkin, Isaac. 2018. “Ranking Firms Using Revealed Preference.”
*Quarterly Journal of Economics* 133(3): 1331–1393.
[doi:10.1093/qje/qjy001](https://doi.org/10.1093/qje/qjy001).

Bradley, Ralph Allan, and Milton E. Terry. 1952. “Rank Analysis of Incomplete
Block Designs: I. The Method of Paired Comparisons.” *Biometrika*
39(3–4): 324–345.
[doi:10.1093/biomet/39.3-4.324](https://doi.org/10.1093/biomet/39.3-4.324).

## Author and license

Johannes F. Schmieder, Boston University.
Repository-authored code and the CMG adaptation are GPL-3.0-only. See
[LICENSE](LICENSE), [NOTICE.md](NOTICE.md) and the recorded third-party
provenance for the Stata plugin interface and CMG source.
