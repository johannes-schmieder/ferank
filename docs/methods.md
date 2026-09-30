# Methods and input contract

## Flow orientation

For origin firm `j` and destination firm `i`, `ferank` defines

```text
M[i,j] = weighted moves from j to i.
```

The destination is therefore the winner in Bradley--Terry comparisons. Both
methods consume exactly the same canonical positive directed edges
`(origin, destination, flow)`.

Prepared-edge rows have unit flow unless `flow()` is supplied. Flow must be
nonnegative and finite. Zero-flow rows and self-moves are excluded and
reported; duplicate directed pairs are sorted and aggregated with compensated
summation. `minflow()` is applied after aggregation.

## Worker-period panels

Panel mode requires one firm per worker and time value. Duplicate worker-time
observations are errors. Observations are ordered internally. A move is formed
between consecutive valid observations only when the firm changes and the time
gap is at most `maxgap()`; its default is one. A missing firm breaks the chain,
same-firm observations are continuations, and every version 0.1 panel move has
unit weight.

Concurrent jobs, dominant-job rules, nonemployment states, recalls, spell
logic, and fractional panel moves must be resolved before calling `ferank`,
usually by preparing an edge list.

## Components and identification

A unique finite score vector (up to an additive constant) requires a strongly
connected positive-flow comparison graph. Components are reported
deterministically. `component(largest)` selects the component with the most
firms, breaking ties by retained flow and then the smallest firm ID.
`component(#)` selects a reported component; `component(all)` estimates every
qualifying component separately. Scores in different components are not
comparable. No component is joined or regularized silently.

## Sorkin

Let `s[j] = sum_i M[i,j]`, `S = diag(s)`, and `P = M S^-1`. The stationary mass
`pi` solves

```text
P pi = pi,       sum(pi) = 1,
```

and the revealed value is `q = S^-1 pi`. The reported score is `log(q)` after
the requested additive normalization. Production uses deterministic sparse
power iteration on `(1-lazy)I + lazy P`, with `lazy(0.5)` by default. Acceptance
is based on both the maximum and L1 residuals against the original equation
`P pi = pi`, plus an alternative-start score-agreement check with gate
`sqrt(tolerance)`; iteration change alone is not a certificate. The L1 gate
does not weaken as the number of firms increases.

## Bradley--Terry

A move from `j` to `i` is one weighted win for `i`. The likelihood is

```text
sum_(i<j) M[i,j] log sigmoid(theta[i]-theta[j])
          + M[j,i] log sigmoid(theta[j]-theta[i]).
```

The score vector is constrained to mean zero while solving. Production uses
overflow-safe Newton/IRLS, an ascent-preserving line search, a dense augmented
KKT solve for bounded systems, and PCG with the audited CMG adapter for larger
systems. Acceptance requires the constrained gradient/KKT certificate and
likelihood stability. Strong connectivity is checked first, so separation is
not reported as convergence.

## Normalization and ranks

`normalize(mean)` sets the unweighted component mean to zero.
`normalize(weighted)` uses a nonnegative firm-level `normweight()` that must be
constant within firm. `normalize(reference)` sets `reference()` to zero. These
rules shift scores but do not alter fitted comparisons.

Larger scores receive better ranks: rank 1 is the highest rank. Exact ties
receive their deterministic midrank and identical percentiles. Firm ID orders
output rows but never breaks an econometric tie.

## Interpreting the two scores

Sorkin asks for the stationary revealed value implied by the entire directed
transition system and adjusts stationary mass by each firm's total outflow.
Bradley--Terry instead asks how often a destination wins conditional on the
unordered firm pair that was compared. The first therefore uses the global
flow propagation structure; the second uses pair-conditional wins. Either can
rank two firms differently without a software inconsistency. Both are
descriptive flow estimands: neither score is a wage effect, structural utility,
amenity, rent, or causal employer value.

## Validation

The bounded `engine(reference)` uses separately implemented dense stationary
and constrained-Newton solvers. Production code is tested for row permutation,
duplicate splitting, firm relabeling, panel rules, component ties, periodic and
nearly reducible chains, extreme logits, separation rejection, deterministic
repetition, and agreement with these dense references.
