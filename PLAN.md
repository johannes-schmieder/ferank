# `firmladder` — Live Development Plan

**Repository:** `johannes-schmieder/firmladder`  
**Primary integration branch:** `main`  
**Primary development environment:** ChatGPT Pro in the web interface  
**Secondary development environment:** local Codex for testing, debugging, benchmarking, and refinement  
**Initial target:** a clean, fast, reproducible Stata package for Sorkin-style revealed-preference firm ladders  

This is the authoritative implementation roadmap and recovery document for the project. It should be updated whenever a substantive design decision is made, a milestone closes, a numerical experiment is retained or rejected, or the recommended next action changes.

Read this file together with:

- `gptpro.md` for the exact-SHA licensed Stata/Rust CI workflow;
- `STATA_CI_RUNNER.md` for the self-hosted Mac Studio environment and security boundary;
- `.ci/stata/latest.json` and `.ci/stata/results/<full-sha>.json` for machine-readable qualification receipts.

---

## 1. Product vision

Create an SSC-quality Stata package that estimates and diagnoses firm ladders from directed worker flows. The first production estimator will implement the Sorkin-style revealed-preference fixed point on a directed employer-mobility graph. The package should be useful on very large matched employer–employee datasets, but remain transparent and trustworthy on small datasets.

The package should make the distinction between three related objects explicit:

1. **Flow-relevant revealed firm value** inferred from directed employer-to-employer moves;
2. **Structural employer value** after additional offer-share, employment-share, destruction, reallocation, or nonemployment adjustments;
3. **Wage, rent, and amenity decompositions** obtained by combining the firm ladder with wage fixed effects or a pairwise-choice model.

Version 0.1 will estimate the first object only. Later versions may add the second and third, but must never relabel the flow fixed point as the full structural object without the required inputs and assumptions.

### Core design principles

- **Econometric definitions are explicit.** Flow construction, component selection, normalization, and weighting must be visible in command syntax and stored results.
- **The numerical result is certified.** Final acceptance uses a residual against the original directed fixed-point equation, not only an iteration-difference stopping rule.
- **Large-data work lives in Rust.** Stata handles syntax, sample marking, result presentation, frames, and postestimation; the Rust plugin handles graph construction and numerical work.
- **Determinism is a feature.** Results must not depend on input row order, duplicate splitting, thread scheduling, or the number of threads, except for documented floating-point differences within strict gates.
- **No hidden regularization.** Teleportation, ridge terms, flow smoothing, or component bridging are never applied silently.
- **One source of truth.** The Rust core defines the production algorithm; a small independent reference implementation validates it on bounded test problems.
- **Checkpoint frequently.** Web development should use small, recoverable commits and exact-SHA CI receipts.

---

## 2. Mathematical target

### 2.1 Directed flow notation

Let `j` denote the origin firm and `i` the destination firm. Define

\[
M_{ij} = \text{weighted flow from firm }j\text{ to firm }i,
\]

with positive finite flow weights. Let total outflow from firm `j` be

\[
s_j = \sum_i M_{ij},
\qquad
S = \operatorname{diag}(s_1,\ldots,s_J).
\]

The Sorkin-style flow value `q` satisfies

\[
S^{-1} M q = q,
\]

or equivalently

\[
M q = S q.
\]

Define the column-stochastic transition operator

\[
P = M S^{-1}.
\]

If `π` is its stationary vector,

\[
P\pi = \pi,
\qquad
\sum_j \pi_j = 1,
\]

then

\[
q = S^{-1}\pi
\]

solves the revealed-value equation. The reported log ladder is

\[
v_j = \log q_j,
\]

followed by an explicit normalization.

### 2.2 Identification domain

The relative value vector is identified on a strongly connected component of the positive-flow directed graph. Version 0.1 will:

1. canonicalize positive directed edges;
2. compute all strongly connected components;
3. select an estimation component under an explicit rule;
4. report all component statistics and the retained share of firms and flows;
5. estimate only where the Perron vector is uniquely defined up to scale.

The provisional default is the largest strongly connected component by number of firms, with ties broken by retained directed flow and then by a deterministic firm-ID rule. This default must be confirmed against the intended empirical convention before the public API is frozen. Options should permit selecting a numbered component or estimating each qualifying component separately.

### 2.3 Lazy iteration without changing the estimand

Directed chains may be periodic or nearly periodic. The production power iteration will use

\[
P_\lambda = (1-\lambda)I + \lambda P,
\qquad 0<\lambda\leq 1,
\]

with a provisional default `λ = 0.5`. `P_λ` has the same stationary vector as `P`, while damping oscillation. Final convergence must be certified against `Pπ = π`, not only `P_λπ = π`.

Google-style teleportation changes the estimand and will not be used by default. Any future regularized method must have a separate method name and explicit documentation.

### 2.4 Normalizations

The underlying `q` is scale invariant. Version 0.1 should support at least:

- `normalize(mean)`: unweighted mean of `v_j` is zero;
- `normalize(weighted)`: weighted mean of `v_j` is zero, using a supplied firm weight;
- `normalize(reference)`: a named reference firm has value zero;
- `normalize(stationary)`: retain `sum(π)=1` and report the implied scale of `q`.

Ranking and percentiles are invariant to additive normalization of `v`. The normalization used must be stored in `e()` and in the result frame metadata.

---

## 3. Version scope

## 3.1 Version 0.1: exact directed-flow ladder

Version 0.1 is deliberately narrow and production-oriented. It will include:

- estimation from an already prepared directed edge list;
- positive integer or fractional flow weights;
- deterministic duplicate aggregation;
- directed strongly connected components;
- Sorkin fixed-point estimation using a sparse lazy power method;
- rigorous fixed-point residual certification;
- normalization, ranking, and percentiles;
- a firm-level result frame;
- comprehensive graph and convergence diagnostics;
- a small independent Mata or dense Rust reference engine for validation;
- a self-contained Rust plugin binary for each supported platform;
- complete Stata help, examples, tests, and package metadata.

Version 0.1 will **not** automatically infer economically endogenous moves from raw histories, estimate offer shares, recover full structural firm values, estimate wage fixed effects, or impose a Bradley–Terry likelihood.

## 3.2 Version 0.2: flow construction and subgroup workflows

Potential version 0.2 additions:

- `firmladder_build` for constructing directed flow tables from worker–firm spells;
- explicit handling of gaps, recalls, concurrent jobs, dominant jobs, firm-ID changes, and nonemployment;
- probability or fractional weighting of moves as endogenous/revealed-preference transitions;
- subgroup and period-specific ladders;
- split-sample stability diagnostics;
- bootstrap orchestration and replication batching;
- optional Arnoldi fallback for exceptionally slow mixing.

## 3.3 Later extensions

Later extensions may include:

- structural employer values using offer shares, employment shares, destruction, reallocation, and nonemployment flows;
- an alternative Bradley–Terry pairwise-move estimator;
- CMG-based wage fixed effects and rent/amenity decompositions;
- analytical influence functions for flows or firms;
- CMG-preconditioned nonsymmetric sensitivity systems where mathematically justified;
- cached multi-period or subgroup workflows sharing graph indexing.

These extensions must remain separate methods or postestimation modules so that the exact Sorkin fixed point remains reproducible and clearly labeled.

---

## 4. Provisional Stata interface

The public API should feel like a standard Stata estimation command and leave the user’s edge data unchanged by default.

### 4.1 Primary edge-list command

Provisional syntax:

```stata
firmladder origin destination [if] [in], flow(varname) [options]
```

For one observation per move, `flow()` may be omitted and each row receives unit weight. Fractional flows must be supported because estimated move-type probabilities may be economically appropriate weights.

Provisional options:

```text
method(sorkin)
component(largest | # | all)
normalize(mean | weighted | reference)
normweight(varname)
reference(value)
lazy(#)
tolerance(#)
maxiter(#)
minflow(#)
minoutflow(#)
threads(#)
engine(plugin | mata)
frame(name)
replace
generate(prefix)
saving(filename)
verbose
```

Exact syntax should be frozen only after prototype use on realistic data.

### 4.2 Output frame

By default the command should create a named firm-level frame rather than attempting to merge firm results into an edge-level dataset. Proposed columns:

```text
firm_id
component_id
in_estimation_component
revealed_value_q
log_revealed_value
stationary_mass
rank
percentile
inflow
outflow
in_degree
out_degree
fixed_point_residual
```

Optional columns may include user-supplied firm weights, normalization offsets, and flags for firms excluded by thresholds.

### 4.3 Stored estimation results

The command should be `eclass` and store at least:

```text
e(cmd)                 firmladder
e(method)              sorkin
e(engine)              plugin or mata
e(N_rows)              marked input rows
e(N_edges_raw)         positive marked directed rows
e(N_edges)             canonical positive directed pairs
e(N_firms_raw)         unique firms before component restriction
e(N_components)        directed strongly connected components
e(N_firms_est)         firms in estimation component
e(flow_total)          total positive flow
e(flow_est)            flow retained in estimation component
e(flow_share_est)      retained flow share
e(component_rule)      selection rule
e(component_id)        selected component identifier
e(iterations)          accepted iterations
e(converged)           convergence flag
e(residual_max)        maximum original-equation scaled residual
e(residual_l1)         L1 fixed-point residual
e(tolerance)           requested tolerance
e(lazy)                damping parameter
e(normalization)       normalization rule
e(normalization_shift) applied log-value shift
e(threads)             actual thread count
e(plugin_version)      backend version
e(runtime_total)
e(runtime_graph)
e(runtime_scc)
e(runtime_solve)
```

The result frame name and any saved output path must also be stored.

### 4.4 Postestimation

Initial postestimation should include:

- `estat components`: component sizes, flow shares, and selection rule;
- `estat convergence`: residual, iterations, damping, and timing;
- `estat stability`: optional rerun from alternative starting vectors or split flows;
- `predict` only if a clear observation-level prediction is defined; do not add a meaningless `predict` merely to mimic regression commands.

### 4.5 Flow builder

`firmladder_build` should be a separate command so that substantive transition definitions are not hidden inside the estimator. Provisional syntax:

```stata
firmladder_build firmvar, worker(workervar) time(timevar) [options]
```

Potential explicit options include:

```text
gap(#)
dominantjob(...)
concurrent(...)
recalls(...)
nonemployment(...)
endogweight(varname)
minimumtenure(#)
from(varname)
to(varname)
flow(varname)
frame(name)
```

This module should be implemented only after the edge-list estimator is stable.

---

## 5. Numerical architecture

## 5.1 Rust workspace

Proposed workspace layout:

```text
Cargo.toml
rust-toolchain.toml
crates/
  firmladder-core/
    src/
      lib.rs
      error.rs
      edge.rs
      graph.rs
      components.rs
      stationary.rs
      normalization.rs
      diagnostics.rs
      reference.rs
  firmladder-plugin/
    src/
      lib.rs
      stata_api.rs
      dispatch.rs
      io.rs
  firmladder-cli/              # optional benchmark/debug binary
    src/main.rs
```

The core crate must be independent of Stata and testable from ordinary Rust. The plugin crate should be a thin translation layer around the core.

### Core modules

- `edge.rs`: checked endpoints, positive finite flow weights, deterministic ordering;
- `graph.rs`: canonicalization, duplicate aggregation, outflows, incoming adjacency;
- `components.rs`: Tarjan or Kosaraju SCC decomposition with deterministic labels;
- `stationary.rs`: lazy sparse power iteration and residual certification;
- `normalization.rs`: log values, weights, reference normalization, ranks;
- `diagnostics.rs`: component, degree, flow, convergence, and timing reports;
- `reference.rs`: bounded dense oracle used only for tests and diagnostics.

## 5.2 Sparse storage

The production stationary update should own rows by destination firm. For each destination `i`, store its incoming origins `j` and flows `M_ij`. Then

\[
(P\pi)_i = \sum_j \frac{M_{ij}}{s_j}\pi_j
\]

can be computed independently for each destination without atomics. This supports deterministic row-parallel evaluation.

Recommended retained layout:

```text
row_offsets: Vec<usize> or checked compact offsets where justified
origins:     Vec<u32> when firm count <= u32::MAX
flows:       Vec<f64>
outflow:     Vec<f64>
```

Input firm IDs remain Stata values. The Rust core remaps them to compact internal indices and preserves a deterministic inverse map.

## 5.3 Canonicalization

Graph construction must:

1. validate marked observations and weights;
2. reject or explicitly drop missing IDs and nonpositive/nonfinite flows;
3. map external IDs to compact internal IDs;
4. sort directed pairs deterministically;
5. aggregate duplicates using compensated summation;
6. report dropped zero/self flow and duplicate compression;
7. build both the SCC adjacency and incoming numerical adjacency without unnecessary retained duplication.

Self-loops contain no pairwise ranking information. The provisional behavior is to remove them from the ranking graph after reporting their total weight. Laziness should be introduced algorithmically, not by silently treating observed same-firm rows as a model parameter.

## 5.4 Strongly connected components

The SCC implementation must be iterative or otherwise safe for very deep graphs. It should return:

- component label for each firm;
- firm count, edge count, and flow totals by component;
- deterministic component ordering;
- selected component under the requested rule;
- diagnostic flags for singleton components and zero-outflow firms.

Tests must include long chains, directed cycles, bow-tie graphs, multiple equal-size components, isolated firms, and permutation-invariant labels after canonical relabeling.

## 5.5 Stationary solver

Version 0.1’s primary solver will be deterministic lazy power iteration.

For each iteration:

1. compute `Pπ` with destination-owned sparse rows;
2. form `(1-λ)π + λPπ`;
3. normalize to positive unit mass;
4. compute an iteration-change norm;
5. periodically compute the original fixed-point residual;
6. accept only when the original residual satisfies the requested tolerance.

Recommended numerical safeguards:

- compensated row summation for high-degree destinations;
- stable normalization when masses span many orders of magnitude;
- explicit checks for NaN, infinity, negative mass, or vanished total mass;
- deterministic fixed-chunk reductions if parallel reductions are used;
- iteration-limit and stagnation diagnostics;
- final rerun of the original operator for certification;
- no success based solely on `|π_{k+1}-π_k|`.

Potential later fallback:

- restarted Arnoldi for slow-mixing cases;
- Anderson acceleration if it preserves positivity and is demonstrably robust;
- both require separate retain/reject gates and independent residual checks.

## 5.6 Reference oracle

Small systems require an independent oracle that does not share the production iteration code. Options include:

- solve an augmented dense stationary system with Gaussian elimination;
- compute a dense eigenvector through a bounded test-only dependency;
- implement a Mata dense reference for Stata integration tests.

The oracle should be limited to small graphs and never become the large-data fallback by accident.

## 5.7 Parallelism

Parallelism is optional and must preserve deterministic results within a strict numerical gate.

Likely parallel targets:

- destination-owned sparse stationary updates;
- large edge sorting/canonicalization;
- independent components when `component(all)` is requested;
- bootstrap or subgroup batches;
- rank/percentile preparation where beneficial.

Avoid atomics for floating-point accumulation. Do not parallelize tiny graphs. Expose `threads()` and report the actual route.

---

## 6. Stata plugin architecture

## 6.1 Boundary responsibilities

Stata should own:

- command parsing and validation;
- `marksample`, `if`, and `in` handling;
- temporary variables and frames;
- user-visible warnings and errors;
- `e()` results, help, and postestimation;
- package installation and plugin selection.

Rust should own:

- ID remapping;
- edge aggregation;
- directed graph construction;
- SCC computation;
- fixed-point solution;
- normalization primitives and ranks;
- detailed machine-readable diagnostics.

## 6.2 Data transfer

The initial plugin API should accept numeric origin and destination IDs plus an optional numeric flow variable. String IDs can be encoded in Stata while preserving a mapping in the output frame.

The plugin should read marked Stata observations directly through the Stata plugin interface and write results into preallocated variables or a compact transfer buffer. Avoid CSV or temporary-file exchange in the normal path.

A versioned request/response contract should include:

```text
ABI version
operation code
marked observation range
variable indices
solver options
thread count
result variable indices
diagnostic scalar slots
error code and bounded error message
```

Every failure crossing the FFI boundary must become a stable Stata return code and explanatory message. Rust panics must never unwind across the C ABI.

## 6.3 Standalone binaries

The distribution target is one self-contained plugin binary per supported Stata platform, with no separately installed Rust runtime or package dependencies.

Initial development platform:

- macOS arm64, Stata/MP 18 on the Mac Studio runner.

Public release targets should include, at minimum:

- macOS arm64;
- macOS x86_64 if supported by intended users;
- Windows x86_64;
- Linux x86_64.

A platform is not declared supported until the plugin loads in Stata and passes an integration smoke test on that platform. Cross-compilation alone is insufficient.

---

## 7. CMG relationship

The Sorkin fixed point is a directed, nonsymmetric eigenproblem. The existing symmetric CMG-PCG solver must **not** be forced into the version 0.1 ranking engine.

CMG is nevertheless highly relevant to later modules:

### 7.1 Wage fixed effects

A worker–firm AKM stage has a weighted bipartite Laplacian normal matrix. CMG can estimate firm wage effects on the same sample and support comparisons among:

- revealed firm value;
- firm wage premiums;
- implied nonpay value;
- rent and compensating-differential components.

### 7.2 Bradley–Terry alternative

For pairwise flows, a Bradley–Terry likelihood has Hessian

\[
H(\theta)
= \sum_{i<j} n_{ij}p_{ij}(1-p_{ij})
(e_i-e_j)(e_i-e_j)',
\]

which is a weighted graph Laplacian. CMG is therefore a natural Newton/IRLS backend for a future `method(bradleyterry)`.

### 7.3 Sensitivity systems

Influence calculations around the directed fixed point produce nonsymmetric constrained systems. An undirected symmetrized flow Laplacian may eventually serve as a CMG preconditioner for GMRES, but only after theoretical and numerical validation.

### 7.4 Licensing

Because planned later modules may link the GPL-3.0-only CMG crate, the provisional package license is **GPL-3.0-only**. The complete license text must be included before public release. Any CMG dependency must be pinned to an audited commit and its provenance recorded.

---

## 8. Testing strategy

## 8.1 Rust unit tests

Required graph tests:

- valid and invalid endpoints;
- missing, zero, negative, NaN, and infinite flows;
- deterministic ID remapping;
- duplicate splitting and row permutation invariance;
- scale invariance of all flows;
- self-loop accounting;
- exact outflow and incoming-row assembly;
- long paths without recursion overflow.

Required SCC tests:

- one directed cycle;
- multiple disconnected cycles;
- bow-tie and source/sink components;
- singleton and isolated firms;
- equal-size tie-breaking;
- invariance under edge permutation and ID relabeling.

Required solver tests:

- known stationary distributions;
- asymmetric two- and three-firm examples;
- periodic cycles with lazy iteration;
- nearly decomposable graphs with weak directed links;
- extreme but finite weights;
- alternative starting vectors;
- final original-equation residual;
- iteration-limit and stagnation errors;
- one-thread versus multi-thread numerical agreement;
- repeatability across runs.

Required normalization tests:

- arithmetic-mean zero;
- weighted-mean zero;
- reference-firm zero;
- invariant ranks and percentiles;
- deterministic tie handling.

## 8.2 Cross-language golden fixtures

Create small synthetic fixtures checked into `tests/fixtures/` containing:

```text
edges.csv or .dta
dense_reference.json
expected_components.json
expected_ladder.json
```

The same fixtures must be consumed by Rust tests and Stata tests. Expected values should come from an independent oracle and include tolerances.

## 8.3 Stata integration tests

Required Stata tests:

- command discovery and plugin loading;
- `if` and `in` behavior;
- missing-value handling;
- unit and fractional flows;
- current data preserved unless explicitly modified;
- result frame creation and replacement semantics;
- exact `e()` metadata;
- stable return codes for invalid input;
- equality to the Mata/dense oracle on small examples;
- permutation and duplicate-splitting invariance;
- help-file examples execute successfully;
- frames and value labels survive expected workflows;
- plugin and reference engines agree within tolerance.

## 8.4 Econometric validation

Before release, add simulation tests that:

1. choose an irreducible transition matrix `P` and outflow vector `s`;
2. compute the known stationary mass `π` and target `q = S^{-1}π`;
3. generate exact or sampled directed flows;
4. recover the normalized ladder;
5. document finite-sample rank and level error.

Additional validation should examine:

- sensitivity to minimum-flow thresholds;
- retained flow share under SCC restriction;
- split-sample rank correlations;
- sparse weak-link identification;
- subgroup ladders with different connected sets;
- interpretation when the largest SCC excludes economically important firms.

## 8.5 Performance tests

Benchmark tiers:

| Tier | Firms | Canonical directed edges | Purpose |
|---|---:|---:|---|
| Small | 1,000 | 10,000 | fast CI and reference comparison |
| Medium | 100,000 | 1,000,000 | ordinary performance qualification |
| Large | 1,000,000 | 10,000,000+ | manual high-memory qualification |

Record separately:

- input scan and ID remapping;
- duplicate aggregation;
- SCC construction;
- selected graph size;
- iteration count;
- stationary solve time;
- normalization/ranking time;
- peak RSS and retained bytes;
- one-, two-, four-, eight-, sixteen-, and twenty-four-thread scaling where hardware permits.

Performance changes are retained only after numerical equivalence, memory, worst-case timing, and full integration gates pass.

---

## 9. CI and development workflow

The repository already has a licensed Stata/MP 18 and Rust self-hosted runner on the Mac Studio. Its exact-SHA receipt is authoritative.

## 9.1 ChatGPT Pro web workflow

For each substantive checkpoint:

1. read `PLAN.md`, `gptpro.md`, `STATA_CI_RUNNER.md`, and current branch state;
2. inspect the newest exact-SHA receipt, not only `.ci/stata/latest.json`;
3. make one focused, reviewable change;
4. commit and push frequently so a long web session is recoverable;
5. record the full source SHA;
6. wait for or inspect the **Licensed Stata and Rust CI** run;
7. require an immutable receipt whose `tested_sha` exactly equals the source SHA;
8. require `status=success`, `stata_status=success`, and `rust_status=success`;
9. fix failures in a new commit rather than rewriting evidence;
10. update this plan or a future `STATUS.md` at every major milestone.

The ChatGPT sandbox must not claim to have executed licensed Stata or local Rust. The self-hosted runner receipt is the evidence.

## 9.2 Local Codex workflow

Local Codex may:

- create a trusted `codex/**` branch;
- run Rust and Stata tests directly on the Mac Studio;
- inspect detailed logs and benchmark locally;
- push focused checkpoints;
- use the same exact-SHA receipt loop;
- merge only a green source SHA into `main`.

Long-lived divergence should be avoided. Experimental branches should either be merged with evidence or deleted after their decision is recorded.

## 9.3 Branch policy

- `main` is the authoritative integration branch and contains this plan.
- Small documentation and tightly scoped implementation checkpoints may be committed directly to `main` when explicitly directed.
- Risky numerical experiments and local Codex work should use `codex/**` branches.
- No deliberate failing checkpoint is merged into `main`.
- Receipt-publisher `[skip ci]` commits are bookkeeping and must not be mistaken for tested source commits.

## 9.4 CI profile evolution

Current profiles are `version`, `smoke`, and `quick`. As the package develops, add explicit profiles without changing machine-level runner configuration:

- `quick`: format, Clippy, Rust unit tests, plugin build, small Stata fixture;
- `full`: all Rust tests, release build, all Stata integration tests, help examples;
- `benchmark`: medium synthetic graph timing and memory records;
- `release`: package manifest, version stamping, checksums, platform artifact validation.

Ordinary pushes should remain bounded. Large benchmarks and release builds should be manual or explicitly path-triggered.

---

## 10. Repository structure

Target structure:

```text
PLAN.md
STATUS.md                         # add when implementation begins
README.md
LICENSE
CITATION.cff
CHANGELOG.md
Cargo.toml
Cargo.lock
rust-toolchain.toml
crates/
  firmladder-core/
  firmladder-plugin/
  firmladder-cli/
stata/
  firmladder.ado
  firmladder.sthlp
  firmladder_estat.ado
  firmladder_build.ado            # later
  firmladder_build.sthlp          # later
  firmladder.pkg
  stata.toc
plugin/
  macos-arm64/
  macos-x86_64/
  windows-x86_64/
  linux-x86_64/
tests/
  fixtures/
  rust/
  stata/
benchmarks/
examples/
docs/
  METHODS.md
  FLOW_CONSTRUCTION.md
  NUMERICAL_CERTIFICATION.md
  PLUGIN_ARCHITECTURE.md
  PERFORMANCE.md
ci/
.ci/
.github/workflows/
```

Generated binaries should not be committed during ordinary development unless the distribution strategy explicitly requires versioned release binaries. GitHub releases may carry platform artifacts and checksums.

---

## 11. Milestones and gates

## M0. Specification and scaffold

**Deliverables**

- [x] repository-scoped licensed Stata/Rust CI bootstrap;
- [x] ChatGPT Pro handoff documentation;
- [x] comprehensive `PLAN.md`;
- [ ] choose provisional public syntax and normalization defaults;
- [ ] choose GPL-3.0-only and install full license text;
- [ ] add workspace, toolchain pin, README, STATUS, and package skeleton.

**Gate**

- exact-SHA `quick` CI green after the first real Rust workspace and Stata command skeleton.

## M1. Mathematical specification and dense oracle

**Deliverables**

- [ ] `docs/METHODS.md` with orientation, equations, component rule, and normalization;
- [ ] bounded independent dense stationary oracle;
- [ ] hand-verified small fixtures;
- [ ] explicit error and residual definitions;
- [ ] test vectors for periodic and nearly reducible graphs.

**Gate**

- oracle reproduces all hand calculations and rejects invalid systems deterministically.

## M2. Rust graph and SCC core

**Deliverables**

- [ ] checked edge ingestion;
- [ ] deterministic ID compression;
- [ ] duplicate aggregation;
- [ ] outflow and incoming sparse rows;
- [ ] iterative SCC decomposition;
- [ ] component diagnostics and selection.

**Gate**

- full graph/SCC tests green under permutation, duplicate splitting, and adversarial graph families.

## M3. Certified Sorkin solver

**Deliverables**

- [ ] lazy sparse power iteration;
- [ ] original-equation residual certification;
- [ ] numerical overflow/nonfinite hardening;
- [ ] normalization, ranks, and percentiles;
- [ ] deterministic optional parallel execution;
- [ ] machine-readable solve report.

**Gate**

- production solver matches the independent oracle on all bounded fixtures and passes medium synthetic tests.

## M4. Stata plugin boundary

**Deliverables**

- [ ] versioned C ABI;
- [ ] macOS arm64 plugin build;
- [ ] direct marked-data ingestion;
- [ ] output-variable or transfer-buffer protocol;
- [ ] stable Stata error codes;
- [ ] panic containment and malformed-request tests.

**Gate**

- Stata loads the plugin and reproduces Rust fixture results under exact-SHA CI.

## M5. `firmladder` edge-list command

**Deliverables**

- [ ] production `.ado` parser;
- [ ] `eclass` results;
- [ ] firm-level result frame;
- [ ] component, convergence, and normalization options;
- [ ] `estat components` and `estat convergence`;
- [ ] help file and executable examples;
- [ ] limited `engine(mata)` validation mode.

**Gate**

- all Stata integration tests and help examples green; input data remain unchanged by default.

## M6. Robustness and econometric validation

**Deliverables**

- [ ] simulated recovery experiments;
- [ ] weak-link and threshold sensitivity tests;
- [ ] alternative starts and damping tests;
- [ ] split-sample workflow;
- [ ] documented component-selection implications;
- [ ] large synthetic graph tests.

**Gate**

- no false convergence, silent component changes, or undocumented normalization behavior.

## M7. Performance qualification

**Deliverables**

- [ ] phase timing and retained-memory reports;
- [ ] deterministic multi-thread route;
- [ ] medium benchmark gates on Mac Studio;
- [ ] 1–24 thread scaling evidence on Mac Studio;
- [ ] large 1M-firm/10M-edge qualification where feasible;
- [ ] performance guide with when to use plugin versus reference engine.

**Gate**

- end-to-end gains justify the plugin architecture, with exact numerical and memory evidence.

## M8. Flow builder

**Deliverables**

- [ ] explicit spell-to-flow specification;
- [ ] `firmladder_build` command;
- [ ] concurrent-job, recall, gap, and nonemployment tests;
- [ ] fractional endogenous-move weights;
- [ ] output compatible with `firmladder` without hidden transformations.

**Gate**

- every flow-construction decision is represented in syntax, metadata, and tests.

## M9. Cross-platform release engineering

**Deliverables**

- [ ] Windows x86_64 plugin and Stata smoke test;
- [ ] Linux x86_64 plugin and Stata smoke test;
- [ ] macOS arm64 release qualification;
- [ ] optional macOS x86_64 qualification;
- [ ] reproducible artifact workflow and SHA-256 checksums;
- [ ] SSC-style package files and GitHub release archive.

**Gate**

- every advertised platform has a licensed-Stata load and numerical integration test.

## M10. Version 1.0 closure

**Deliverables**

- [ ] final source audit;
- [ ] final documentation and help audit;
- [ ] full GPLv3 text and provenance records;
- [ ] citation metadata and methodological references;
- [ ] changelog and semantic versioning;
- [ ] clean repository with obsolete one-shot workflows removed;
- [ ] tagged release and installation instructions.

**Definition of complete**

Version 1.0 is complete only when:

- the exact Sorkin flow-value equation is implemented and documented;
- all successful results carry an original-equation residual certificate;
- SCC restriction and retained flow shares are explicit;
- small results match an independent oracle;
- medium and large tests show predictable memory use;
- Stata integration is green on every supported platform;
- the package installs cleanly and all documented examples run;
- no known critical numerical, API, licensing, or interpretation defect remains.

---

## 12. Documentation plan

### `README.md`

- concise purpose and scope;
- installation;
- minimal edge-list example;
- interpretation boundary between flow value and structural value;
- supported platforms and development status.

### `docs/METHODS.md`

- complete notation and orientation;
- Perron/stationary-distribution equivalence;
- SCC identification;
- normalization;
- residual and convergence definitions;
- differences between Sorkin, Bradley–Terry, and wage-FE methods.

### `docs/FLOW_CONSTRUCTION.md`

- moves versus all transitions;
- job-to-job definition;
- gaps and nonemployment;
- recalls and firm-ID changes;
- concurrent jobs and dominant-employer rules;
- fractional move weights;
- minimum-flow thresholds;
- subgroup-specific graphs.

### `docs/NUMERICAL_CERTIFICATION.md`

- exact residuals;
- determinism;
- handling of periodicity;
- nonfinite and overflow errors;
- reference oracle;
- precision limits.

### `docs/PERFORMANCE.md`

- benchmark hardware;
- graph sizes and flow distributions;
- thread routing;
- phase timing and memory;
- qualification boundaries.

---

## 13. Risk register

### R1. Orientation mistakes

**Risk:** Origin/destination conventions can transpose the operator and reverse interpretation.  
**Mitigation:** One canonical notation, hand-worked asymmetric fixtures, and stored orientation metadata.

### R2. Mislabeling the estimand

**Risk:** Flow-relevant value may be presented as full structural firm value.  
**Mitigation:** Command, variables, help, and docs use `flow_value` or `revealed_value`; structural mode is a separate later feature.

### R3. Component selection drives results

**Risk:** The largest SCC may exclude important firms or vary across groups.  
**Mitigation:** Always report all component sizes and flow shares; expose selection options; never silently bridge components.

### R4. Slow mixing

**Risk:** Nearly decomposable directed graphs can require many power iterations.  
**Mitigation:** Lazy operator, residual monitoring, stagnation diagnostics, optional later Arnoldi fallback, and no false success.

### R5. Extreme dynamic range

**Risk:** Very unequal flows may overflow, underflow, or erase small stationary masses.  
**Mitigation:** checked finite arithmetic, stable normalization, compensated sums, adversarial tests, and explicit failure.

### R6. Hidden substantive choices in flow construction

**Risk:** Convenience code may silently define recalls, gaps, or concurrent jobs.  
**Mitigation:** separate builder command, explicit options, detailed metadata, and edge-list estimator as the canonical core.

### R7. Stata plugin ABI and platform differences

**Risk:** A binary may compile but fail to load or behave differently across Stata platforms.  
**Mitigation:** thin ABI, no unwind across FFI, platform-specific licensed-Stata smoke tests, and checksummed releases.

### R8. CI bookkeeping confusion

**Risk:** Receipt-publisher commits may be mistaken for tested source.  
**Mitigation:** require the exact full `tested_sha` receipt for every qualification claim.

### R9. Scope expansion

**Risk:** Structural values, CMG, AKM, Bradley–Terry, and flow building delay a clean first release.  
**Mitigation:** freeze version 0.1 around the exact directed-flow estimator; stage all extensions after the core is production-ready.

---

## 14. Initial decisions

The following defaults are adopted for planning and should be revisited only with explicit evidence or owner direction:

1. Package and main command name: **`firmladder`**.
2. Version 0.1 method: exact Sorkin-style directed fixed point.
3. Canonical input: prepared directed edge list.
4. Numerical backend: Rust plugin; bounded reference engine for validation.
5. Output: firm-level Stata frame plus `eclass` diagnostics.
6. Periodicity treatment: lazy iteration, provisional `λ=0.5`.
7. No hidden teleportation, ridge, smoothing, or component bridging.
8. CMG is not used for the nonsymmetric version 0.1 fixed point.
9. CMG integration is reserved for wage-FE and Bradley–Terry extensions.
10. Provisional license: GPL-3.0-only.
11. `main` is the authoritative integration branch; local experiments may use trusted `codex/**` branches.
12. Exact-SHA licensed Stata/Rust receipts are required for qualification claims.

---

## 15. Decisions requiring owner sign-off before API freeze

These do not block initial scaffolding, but must be resolved before version 0.1 syntax and help are declared stable:

1. **Default SCC rule:** largest by firm count, employment, or retained directed flow.
2. **Default normalization:** unweighted mean log value zero or employment-weighted mean zero.
3. **Minimum supported Stata version:** begin with Stata 18 on the runner, then decide whether public support should extend to Stata 16 or 17.
4. **Primary output behavior:** always create a result frame, or permit a firm-level input mode that generates variables in place.
5. **Fractional-flow syntax:** `flow(varname)` only, or also Stata weight syntax.
6. **Version 0.1 panel convenience:** edge list only, or include a deliberately minimal raw-transition mode.
7. **Public package scope:** rank-only initial release versus including split-sample diagnostics in version 0.1.
8. **Cross-platform release order:** macOS arm64 first, then Windows and Linux together or sequentially.
9. **CMG dependency strategy:** pinned Git dependency, workspace sibling, or vendored audited source when later extensions begin.

Record the final answers in this plan’s decision log and in user-facing documentation.

---

## 16. Immediate next actions

1. Create the Rust workspace and pin the Rust toolchain.
2. Add `README.md`, `STATUS.md`, full GPLv3 license text, and package skeleton.
3. Write `docs/METHODS.md` with a single unambiguous orientation convention.
4. Implement the independent dense oracle and hand-worked fixtures before the production sparse solver.
5. Implement deterministic edge canonicalization and SCC decomposition.
6. Extend the existing `quick` CI profile to run the real Rust workspace and the first Stata package smoke test.
7. Require an exact-SHA green receipt before moving from each milestone to the next.

The first production-code milestone should not begin with Stata syntax or performance tuning. It should begin with a mathematically pinned oracle and adversarial directed-graph fixtures so that every later optimization is judged against a trusted target.
