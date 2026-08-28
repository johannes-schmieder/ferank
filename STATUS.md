# ferank implementation status

Last updated: 2026-08-28

The repository contains an alpha implementation of the version 0.1 plan:

- deterministic prepared-edge and worker-period ingestion;
- stable numeric/string firm-ID mapping at the Stata boundary;
- duplicate aggregation, filtering, SCC discovery, and component selection;
- certified Sorkin sparse lazy iteration;
- certified Bradley--Terry Newton/IRLS with dense KKT and PCG/CMG routes;
- independent bounded dense reference engines and asymmetric fixtures;
- mean, firm-weighted, and reference-firm normalization;
- a transactional Stata `eclass` command, result frame, and
  `estat components`/`estat convergence`;
- a native macOS Stata plugin build and licensed quick-test suite.

Local Rust tests, strict Clippy, the native macOS build, licensed local
Stata/MP 18 quick tests, and the planned 100,000/1,000,000 and
1,000,000/10,000,000 synthetic performance sizes pass. This working tree is
not a qualified release until its exact committed SHA has an immutable green
CI receipt. Peak-RSS capture and licensed Windows/Linux artifact qualification
remain release gates.
