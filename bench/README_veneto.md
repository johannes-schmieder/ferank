# Full private Veneto benchmark

`veneto_full.do` compares AKM wage effects estimated by `fereg` with Sorkin
and Bradley--Terry rankings estimated by `ferank`. It creates four full firm-level scatter plots and four separate binned
scatter plots in Stata, timing/certificate tables, and a clean report through
`latexlog`.

The input is the **private, full FEVC 1996--2001 panel**, not the public
LeaveOutKSS teaching extract. It contains 5,163,428 observations, 1,106,419
workers, 86,647 firms and 1,700,466 worker-firm matches. The prepared CSV has
SHA-256 `e4a1928d98c1dbe7185634e14470b9361b58f8d5b33cceacc8d168ccdad4634e`.
The validated input must be obtained separately through its authorized data
access arrangements; this repository does not distribute it.
Keep the input outside the repository and do not run this task in GitHub CI.

Run from the ferank root on the licensed Mac, after building both packages:

```sh
python3 scripts/run_veneto_benchmark.py /private/path/pooled_adjusted_1996_2001.csv \
  --output "$PWD/report/output/veneto-sorkin-RUN_ID" \
  --threads 1 8 --repetitions 3 --sample sorkin
```

The launcher stages the existing built plugins and all package ado files in
the ignored private output directory. It checks the input hash, records source
revisions and dirty status, hashes staged files, and verifies Stata's explicit
status and PASS marker. The existing plugin hash identifies the executed
binary; the current Git revision alone cannot establish its build provenance.
Set `LATEXLOG_DIR` if latexlog is not in the usual local Stata PLUS folder.

Direct Stata entry point:

```stata
do bench/veneto_full.do "/private/path/pooled_adjusted_1996_2001.csv" ///
    "/private/output/directory" "/path/to/fereg" "/path/to/ferank" 3 "1 8" full sorkin
```

Direct execution does not snapshot dependencies; the launcher is preferred
when other development sessions may edit them. Paths must be absolute.
Native thread requests may range from 1 to 16 on this Mac; the do-file keeps
Stata within its licensed processor count. The source input and tolerances are fixed. The default `sorkin` profile applies
the documented restrictions below; `--sample full` retains the unfiltered input.
All new reports use person-year weights.

Timing protocol:

- One initial call plus three measured calls per estimator and thread setting.
- Measured order rotates across AKM, Sorkin and Bradley--Terry. All calls are
  sequential, with the selected panel resident in Stata.
- Complete-command time includes AKM saved firm effects/residuals and ferank's
  panel construction/result frame. Import, sample checks, output validation,
  comparisons, graphics and report compilation have separate boundaries.
- Initial calls are shown separately. Only the first thread setting starts
  before AKM is loaded. In `sorkin` mode, an untimed selection call already
  loads ferank. Initial calls are not fresh-process cold starts.
- Internal graph/input and solver timings are retained as diagnostics, with
  their different package-specific boundaries stated in the report.
- Repeated and cross-thread firm score vectors are compared after centering
  at `1e-8*max(1,abs(score))`. Successful flow outputs require their numerical
  certificates; failed estimation stops the run and leaves its evidence.

The `sorkin` profile counts nonsingleton person-years in the original full
panel: a worker is observed again at a later year, so each worker's terminal
observation is excluded from this count. A firm needs at least 90 such rows
(Sorkin 2018, pp. 1341--1342). After filtering firms, an untimed ferank call
selects the largest directed SCC. AKM and both flow methods are then refitted
on all rows at those firms, including terminal rows and eligible stayers.
With `maxgap(1)`, dropping an intermediate annual observation cannot invent a
new transition. The selection-score vector must agree with the induced graph.

Firm person-year counts (including terminal observations) weight Pearson
correlations, weighted Spearman, rank percentiles, 20 weighted AKM quantile
bins, bin means and top-decile overlap (Table II notes, p. 1344). Weighted
Spearman uses weighted empirical-CDF midranks, equivalent to expanding integer
frequency weights; the paper's final-table rank routine is not in its public
replication archive. Equal-firm correlations remain in `correlations.csv` as
a diagnostic. Flow edges retain unit move counts; the estimators themselves
are not employment-weighted. Raw scatter marker sizes reflect person-years.

AKM uses FEVC's pre-adjusted log wage and worker/firm effects. Year effects
and normalized cubic age terms were jointly fitted in the prior full-panel
preparation; these nuisance parameters are not reestimated on the restricted
sample. The annual input cannot reproduce quarterly direct EE overlap,
nonemployment-hiring or bootstrap-coverage restrictions. This is a closer
sample and weighting comparison with Sorkin's unadjusted flow value, not a
replication of the full structural model or its amenity decomposition.

Outputs under the owner-only directory include:

- `veneto_benchmark.tex` and `veneto_benchmark.pdf`;
- `figures/akm_{sorkin,bt}_{rank,score}.png` at 2,600-pixel width;
- `figures/akm_{sorkin,bt}_{rank,score}_binned.pdf` as vector graphics, using
  20 person-year-weighted AKM quantile bins on the selected common component;
- the same bin means and firm counts in `binned_scatter_data.csv` and `.dta`;
- firm eligibility audit in `sample_firm_counts.dta`, a selected-score reference
  in restricted runs, and weighted/equal-firm results in `correlations.csv`;
- all individual calls in `timings.csv` and medians/ranges in `timing_summary.csv`;
- private firm-level `.dta` comparisons and baseline estimates;
- input checks, `run_manifest.json`, explicit Stata status/log, and whole-process
  elapsed time in `execution.json`.

To regenerate graphics and the report without refitting:

```sh
python3 scripts/run_veneto_benchmark.py /private/path/pooled_adjusted_1996_2001.csv \
  --output "$PWD/report/output/veneto-sorkin-RUN_ID" --report-only
```

The `report` mode of the do-file is equivalent. Report-only revisions use a
separate `report_code/` tree and preserve all original benchmark snapshots,
plugins and measured timings. A fresh strict pdflatex pass must succeed before
the report is accepted; compilation logs remain available for layout checks.
