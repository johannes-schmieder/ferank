# `ferank` — Live Development Plan

**Repository:** `johannes-schmieder/ferank`

**Primary branch:** `main`

**Product:** an SSC-quality Stata package for firm rankings constructed from
directed worker flows

**Version 0.1 methods:** Sorkin and Bradley–Terry

This is the authoritative implementation roadmap and recovery document. Read
it with `gptpro.md`, `STATA_CI_RUNNER.md`, and the exact-SHA receipts under
`.ci/stata/results/`. Update it when a substantive design decision changes, a
milestone closes, or the recommended next action changes.

---

## 1. Product boundary

`ferank` constructs comparable firm scores and rankings from observed directed
worker moves. Version 0.1 supports two estimators over one canonical flow graph:

1. the Sorkin revealed-preference fixed point; and
2. a Bradley–Terry pairwise-choice likelihood in which the destination firm
   wins each observed origin-to-destination comparison.

Both estimators accept either a prepared directed edge list or a simple
worker–firm period panel. Both return normalized scores, ranks, percentiles,
graph coverage, and method-specific fit or convergence diagnostics.

Version 0.1 is point-estimation software. It does not estimate structural
employer values, offer shares, wage fixed effects, rents, amenities, standard
errors, bootstrap intervals, or influence functions. Those topics are outside
this roadmap rather than deferred modules.

### Design rules

- Flow orientation and construction are explicit and stored with every result.
- The same canonical directed flow matrix feeds both methods.
- Successful numerical results carry a method-specific certificate against the
  original estimating equation or likelihood first-order condition.
- Component selection, filtering, normalization, and weighting are never
  hidden.
- Input order, duplicate edge splitting, and thread scheduling must not change
  the result outside strict documented floating-point gates.
- Rust owns graph and numerical work; Stata owns syntax, sample marking,
  frames, stored results, and user-visible errors.
- The production Rust implementations are checked against independent bounded
  reference solvers.

---

## 2. Canonical flow input

Let `j` be the origin firm and `i` the destination firm. Define

\[
M_{ij}=\text{weighted number of observed moves from }j\text{ to }i.
\]

All marked inputs are converted to a canonical table of positive directed
edges `(origin, destination, flow)`. External firm IDs are mapped to stable
compact indices and mapped back in the result frame.

### 2.1 Prepared edge-list mode

Provisional syntax:

```stata
ferank origin destination [if] [in], method(sorkin|bradleyterry) ///
    [flow(varname) options]
```

- Each row has unit flow when `flow()` is omitted.
- `flow()` accepts positive finite integer or fractional weights.
- Duplicate directed pairs are aggregated deterministically with compensated
  summation.
- Missing firm IDs, negative weights, and nonfinite weights are errors.
- Zero-weight rows and self-moves carry no ranking information; they are
  excluded and reported.
- `minflow()` is applied to canonical edge totals before component selection.

### 2.2 Worker–firm period-panel mode

Provisional syntax:

```stata
ferank firm [if] [in], worker(workervar) time(timevar) ///
    method(sorkin|bradleyterry) [maxgap(#) options]
```

Version 0.1 deliberately supports one narrow panel contract:

- one nonconcurrent firm assignment per worker and time value;
- duplicate worker–time observations are an error;
- observations are ordered internally without changing the caller's data;
- repeated observations at the same firm form one continuing employment run;
- a move is recorded only when two consecutive valid worker observations have
  different nonmissing firms and their time difference is at most `maxgap()`;
- `maxgap(1)` is the default;
- an observed missing firm always breaks the transition chain, even when a
  larger `maxgap()` is requested;
- same-firm transitions produce no edge;
- each constructed move receives unit weight in version 0.1.

Users needing concurrent-job rules, dominant-job selection, spell start/end
logic, nonemployment states, recalls, or fractional move weights must prepare
an edge list outside `ferank`. The command reports panel rows, workers, valid
moves, gap breaks, missing-firm breaks, and same-firm continuations.

### 2.3 Identification components

Both methods require a strongly connected positive-flow directed comparison
graph for a unique finite score vector up to an additive normalization.
`ferank` therefore:

1. canonicalizes edges;
2. computes all directed strongly connected components;
3. orders components deterministically;
4. selects the requested estimation component; and
5. reports retained firms, edges, and flow.

The default `component(largest)` chooses the component with the most firms,
breaking ties by retained flow and then the smallest canonical firm ID.
`component(#)` selects a reported component. `component(all)` estimates every
qualifying component separately and clearly marks scores and ranks as
component-specific and not comparable across components. No component is
bridged or regularized silently.

---

## 3. Ranking methods

### 3.1 Sorkin

Let

\[
s_j=\sum_i M_{ij},\qquad S=\operatorname{diag}(s_1,\ldots,s_J).
\]

The Sorkin flow value `q` satisfies

\[
Mq=Sq.
\]

With the column-stochastic transition matrix `P=MS^{-1}`, its stationary mass
`pi` satisfies

\[
P\pi=\pi,\qquad \mathbf{1}'\pi=1,
\]

and `q=S^{-1}pi`. The reported method score is

\[
v_j=\log q_j
\]

after the requested additive normalization.

The production solver uses deterministic sparse power iteration on

\[
P_\lambda=(1-\lambda)I+\lambda P,
\]

with default `lazy(0.5)`. Laziness preserves the estimand while controlling
periodicity. Success requires an explicit residual against `P pi = pi`, not
only a small iteration difference. Teleportation, ridge terms, smoothing, and
component bridging are not allowed.

Required Sorkin diagnostics include iterations, damping, maximum and L1
fixed-point residuals, alternative-start agreement in validation mode, phase
timing, and stationary-mass range.

### 3.2 Bradley–Terry

A move from `j` to `i` is a win for `i`. For each unordered compared pair, the
log-likelihood is

\[
\ell(\theta)=\sum_{i<j}\left[
M_{ij}\log \sigma(\theta_i-\theta_j)+
M_{ji}\log \sigma(\theta_j-\theta_i)
\right],
\]

where `sigma(x)=1/(1+exp(-x))`. Higher `theta` means the firm wins more revealed
preference comparisons, conditional on the compared pair.

The production solver uses stable Newton/IRLS with:

- overflow-safe logistic and log-likelihood evaluation;
- a mean-zero constrained score vector;
- deterministic sparse gradient and Laplacian-Hessian assembly;
- an ascent-preserving line search;
- a dense direct solve for bounded systems;
- PCG for large Newton systems, preconditioned by the audited CMG core; and
- acceptance only when the constrained gradient/KKT residual and likelihood
  change satisfy their gates.

The CMG implementation will be internalized from the tracked Rust source at
`johannes-schmieder/vckss` commit
`5f6e3d4da84f638e866baca2c0c7707205d2182b`, path
`rust/crates/vckss-core/src/cmg.rs`, Git blob
`0bc4dfc8da7e7d8cc5de2389ade69280b0dc52a6`, SHA-256
`54571c61a85a4fb74f090bb93f41489ed225f4a7784be01f03b697656b0d053a`.
Only that tracked blob is a source; uncommitted sibling-worktree changes are
not. The copy must retain GPL-3.0-only licensing, notices, and a provenance
manifest, and must be adapted behind a narrow `ferank` Laplacian-solve API.

Required Bradley–Terry diagnostics include log-likelihood, iterations, line
search steps, constrained gradient norm, Newton-system residual, CMG route,
and phase timing. Strong connectivity is checked before solving so a
separation-driven infinite maximum is never reported as convergence.

### 3.3 Scores, normalization, and ranks

The common `score` column contains `log(q)` for Sorkin and `theta` for
Bradley–Terry. The default `normalize(mean)` sets the unweighted component mean
score to zero. Also support:

- `normalize(weighted)` with `normweight()` supplied at firm level; and
- `normalize(reference)` with `reference()`.

Higher scores always mean higher rank. Equal scores receive deterministic
midranks and identical percentiles; firm ID orders display rows but never
breaks an econometric tie. Rank and percentile are computed within the
estimation component.

---

## 4. Stata result contract

The single public command is `ferank`; `method()` is required and has no
default. Shared provisional options are:

```text
component(largest | # | all)
normalize(mean | weighted | reference)
normweight(varname)
reference(value)
minflow(#)
tolerance(#)
maxiter(#)
threads(#)
engine(plugin | reference)
frame(name)
replace
verbose
```

`lazy()` is Sorkin-specific. The reference engine is bounded and intended for
validation, not large-data fallback.

The command leaves the caller's data unchanged and creates a firm-level result
frame with at least:

```text
firm_id
method
component_id
in_estimation_component
score
rank
percentile
inflow
outflow
in_degree
out_degree
```

Sorkin additionally returns `revealed_value_q`, `stationary_mass`, and the
firm-level fixed-point residual. Method-specific iteration and fit information
lives in `e()` rather than being forced into meaningless common columns.

The command is `eclass` and stores `e(cmd)=ferank`, method, input mode, marked
rows, raw and canonical edges, firms, component counts and rule, retained flow,
normalization, convergence certificate, thread route, backend version, result
frame, and phase timings. Initial postestimation is limited to
`estat components` and `estat convergence`. There is no `predict` command in
version 0.1.

Recognized failures use stable return codes and must not leave a partial result
frame or modified caller data.

---

## 5. Numerical and plugin architecture

The planned Rust workspace is:

```text
crates/
  ferank-core/
  ferank-plugin/
  ferank-cli/        # bounded oracle and benchmark driver
```

`ferank-core` owns:

- checked edge and panel-move ingestion;
- stable ID compression and duplicate aggregation;
- incoming and outgoing sparse graph layouts;
- iterative directed SCC decomposition;
- shared component selection and ranking utilities;
- the certified Sorkin solver;
- the certified Bradley–Terry solver and CMG adapter;
- normalization and deterministic midranks; and
- machine-readable diagnostics.

Destination-owned incoming rows are the primary Sorkin layout, allowing each
`P*pi` destination to be computed without floating-point atomics. The
Bradley–Terry layer stores canonical unordered pairs and directed win counts.
Graph construction reuses compact indices and retained flow totals across both
methods.

`ferank-plugin` is a thin, versioned Stata SPI boundary. It reads marked
numeric variables directly, contains panics before the C ABI, validates all
buffer dimensions and operation codes, and maps bounded backend errors to
stable Stata return codes. String firm IDs are encoded in Stata with a mapping
preserved in the result frame.

Stata owns parsing, `marksample`, frames, value-label preservation, `e()`
results, display, help, and transactional rollback. CSV and temporary-file
exchange are not used in the normal path.

The package and internalized CMG source are GPL-3.0-only. Public release
requires the full license, corresponding source, notices, provenance review,
and a reviewed Stata SPI redistribution boundary.

---

## 6. Testing and qualification

### Independent oracles

- A bounded dense stationary-system oracle validates Sorkin.
- A separately implemented dense constrained Newton solver validates
  Bradley–Terry.
- Shared hand-worked asymmetric fixtures pin flow orientation and the rule that
  destinations are Bradley–Terry winners.
- Oracle code must not call production graph assembly or production solvers.

### Required properties

Both methods must test:

- edge and panel row permutation invariance;
- duplicate-edge splitting invariance;
- firm-ID relabeling invariance;
- unit and fractional prepared flows;
- missing, zero, negative, and extreme flow handling;
- self-move accounting;
- directed cycles, disconnected components, weak links, and equal-size
  component ties;
- repeatability across runs and strict one-thread/multi-thread agreement;
- transactional Stata failure and unchanged caller data; and
- exact agreement with the independent oracle on bounded fixtures.

Panel tests additionally cover repeated same-firm periods, actual moves,
duplicate worker-time errors, missing-firm breaks, default adjacent periods,
and explicit `maxgap()` behavior.

Sorkin tests cover periodic chains, nearly reducible graphs, alternative
starts, stagnation, and original-equation residuals. Bradley–Terry tests cover
balanced and one-sided comparisons, separation rejection, stable extreme
logits, monotone line search, Newton-system certification, and CMG-versus-dense
agreement.

### Performance gates

Use small CI fixtures, a manual medium graph near 100,000 firms and 1,000,000
canonical edges, and a manual large graph near 1,000,000 firms and 10,000,000
edges. Record ingestion, canonicalization, SCC, solve, ranking, peak RSS,
iterations, and 1/2/4/8/16/24-thread scaling. Retain an optimization only after
numerical equivalence, memory, and worst-case timing gates pass.

### CI evidence

Every accepted checkpoint requires an immutable receipt whose `tested_sha`
equals the source commit and whose overall, Stata, and Rust statuses are all
`success`. `.ci/stata/latest.json` is only a pointer. Ordinary pushes remain
bounded; full, benchmark, and release qualification are explicit profiles.

No platform is advertised until a self-contained plugin loads and passes the
same Stata numerical fixtures there. Development begins with licensed Stata/MP
18 on macOS arm64; Windows x86_64 and Linux x86_64 are release gates.

---

## 7. Milestones

### M0. Rename and specification

- [x] Licensed Stata/Rust CI bootstrap.
- [x] Rename repository, runner, and project identity to `ferank`.
- [x] Freeze the roadmap around Sorkin and Bradley–Terry flow rankings.
- [ ] Add README, STATUS, GPL-3.0-only license, toolchain pin, and package
  skeleton.

**Gate:** renamed infrastructure publishes an exact-green receipt containing
the `ferank` repository, runner, and smoke marker.

### M1. Shared graph and dense oracles

- [ ] Pin the mathematical orientation and panel-to-edge contract in methods
  documentation.
- [ ] Implement both independent dense oracles and hand-worked fixtures.
- [ ] Implement deterministic edge/panel ingestion, ID compression, SCCs, and
  component diagnostics.

**Gate:** adversarial graph and panel fixtures pass both oracles and shared
canonicalization properties.

### M2. Certified Sorkin method

- [ ] Implement sparse lazy iteration, original-equation residuals,
  normalization, ranks, and diagnostics.
- [ ] Match the dense oracle and pass medium synthetic graphs.

### M3. Certified Bradley–Terry method

- [ ] Internalize the pinned CMG source with provenance and license notices.
- [ ] Implement dense and CMG-preconditioned Newton/IRLS routes, line search,
  separation checks, and KKT certification.
- [ ] Match the dense oracle and pass medium synthetic graphs.

### M4. Stata command and plugin

- [ ] Implement both syntax branches, the versioned ABI, transactional result
  frame, `eclass` results, and two `estat` commands.
- [ ] Execute all help examples and cross-language fixtures in licensed Stata.

### M5. Performance and robustness

- [ ] Qualify deterministic parallel routes, weak-link behavior, large graphs,
  memory bounds, and panel ingestion scale.
- [ ] Document interpretation differences between the two flow scores without
  introducing non-flow estimands.

### M6. Cross-platform release

- [ ] Qualify macOS arm64, Windows x86_64, and Linux x86_64 plugin artifacts in
  licensed Stata.
- [ ] Complete packaging, checksums, license/provenance review, help audit, and
  SSC-style installation metadata.

Version 1.0 is complete only when both methods are documented, independently
validated, numerically certified, deterministic within their gates, usable
from both supported input modes, and qualified on every advertised platform.

---

## 8. Fixed decisions and immediate work

The following decisions are fixed unless the owner explicitly changes them:

1. Package and command name: `ferank`.
2. Version 0.1 methods: Sorkin and Bradley–Terry with required `method()`.
3. Inputs: prepared directed edges or the narrow worker-period panel contract.
4. Panel default: adjacent periods only, `maxgap(1)`, and missing firms break
   transitions.
5. Default component: largest directed SCC by firms, then flow, then firm ID.
6. Default normalization: unweighted mean score zero.
7. Output: point scores, midranks, percentiles, coverage, and diagnostics; no
   inference.
8. Backend: Rust plugin plus bounded independent reference engines.
9. Bradley–Terry large-system backend: the pinned GPL-3.0-only CMG core.
10. No hidden smoothing, teleportation, ridge, or component bridging.
11. Exact-SHA licensed Stata/Rust receipts are the qualification evidence.

Immediate implementation begins with the shared orientation fixtures and two
independent dense oracles, followed by canonical graph construction. Public
syntax and performance work must not outrun those scientific references.
