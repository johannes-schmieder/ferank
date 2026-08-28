# Technical companion report

`ferank_technical_report.tex` is the long-form companion to the Stata help
file. It explains the graph terminology, the Sorkin and Bradley--Terry
estimators, the command contract, diagnostics, and a reproducible application
to the public Veneto-based `LeaveOutKSS` teaching extract.

Build the complete report on the licensed macOS development host:

```sh
report/replication/run_report.sh
```

The driver hash-verifies and stages the public example, builds the native
plugin, runs both estimators in Stata, regenerates aggregate vector figures and
tables, and compiles the PDF. Set `FERANK_VENETO_SOURCE` to an existing copy of
the CSV or CRAN source archive to build without downloading the data. Raw data,
Stata result files, LaTeX intermediates, and the compiled PDF are intentionally
ignored; the disclosure-safe generated exhibits under `report/generated/` are
versioned.

The public file is a pseudonymous teaching extract distributed with the R
package, not the confidential Veneto Workers History analysis sample. Its
SHA-256 is pinned in `replication/stage_veneto_example.py`.
