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

Implementation commit `e4ec1ff7aa34a3d6b9091e0da4e73d5a97aaec74` has an
immutable quick-profile receipt with both licensed Stata and Rust statuses
equal to `success`. Local strict checks, the universal x86_64/arm64 macOS
build, licensed Stata/MP quick tests, and the planned 100,000/1,000,000 and
1,000,000/10,000,000 synthetic performance sizes pass. This working tree is
an alpha checkpoint rather than a qualified release. Peak-RSS capture and
licensed Windows/Linux artifact qualification remain release gates; the
Windows run is currently blocked by repair of the restricted short-lived
credential profile.
