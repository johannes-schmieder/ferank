{smcl}
{* *! version 0.1.0 30sep2026}{...}
{vieweralsosee "ferank" "help ferank"}{...}
{.-}
help for {cmd:ferank postestimation} {right:(Johannes F. Schmieder)}
{.-}

{title:Title}

{pstd}
{cmd:ferank postestimation} {hline 2} Graph coverage and numerical certificates

{pstd}
{help ferank_postestimation##syntax:Syntax} |
{help ferank_postestimation##components:Components} |
{help ferank_postestimation##convergence:Convergence} |
{help ferank_postestimation##results:Using generated variables}

{marker syntax}
{title:Syntax}

{p 8 16 2}{cmd:estat components}

{p 8 16 2}{cmd:estat convergence}

{pstd}
Both commands display stored results from the preceding successful
{help ferank} estimate. They do not refit the model, change the sample,
or generate additional results in {cmd:r()}. They require estimation
results with {cmd:e(cmd)} equal to {cmd:ferank}; run them before fitting
another model or using {cmd:ferank, version} or {cmd:ferank, selftest}.

{marker components}
{title:estat components}

{pstd}
Displays the number of strongly connected components in the full canonical
directed graph ({cmd:e(N_components)}), the requested selection rule
({cmd:e(component)}), ranked firms ({cmd:e(N_results)}), separately estimated
components ({cmd:e(N_components_estimated)}) and mapped observations
({cmd:e(N_mapped)}).
The component count includes single-firm components, which cannot be
estimated. The display is a summary, not a table of every component or an
observation-level sample indicator.

{pstd}
{cmd:e(N_firms)} and {cmd:e(N_edges)} count firms and edges after flow
aggregation and {cmd:minflow()} filtering, but before component selection.
Generated values are present only on selected rows whose firm belongs to an
estimated component. In flow mode, endpoints are mapped independently; the
display also gives origin and destination coverage. After {cmd:component(all)},
use the variables saved with {cmd:componentid()} to distinguish groups. Scores and percentiles from different components are not
comparable. See {help ferank##sample:Flow sample} for selection details.

{marker convergence}
{title:estat convergence}

{pstd}
Displays the method, certificate status, and maximum iteration count across
selected components. An accepted estimate has
{cmd:e(convergence_certificate)} equal to {cmd:success}. A failed solve
returns an error and does not publish a partial ranking. If a failed command
leaves an earlier estimate in {cmd:e()}, that earlier certificate does not
describe the failed command.

{dlgtab:Sorkin}

{pstd}
The display shows {cmd:e(residual_max)} and {cmd:e(residual_l1)}. These are
the largest component maximum-absolute and L1 norms of the original
stationary-equation residual {cmd:P*pi-pi}; P sends mass from origins to
destinations. Production estimation requires both norms to be no greater
than the requested {cmd:tolerance()}, and checks agreement from alternative
starting masses. It does not accept a small iteration change alone.
The bounded direct reference engine uses a component-size-scaled residual
gate. Firm-level signed residuals are not published as variables.

{dlgtab:Bradley--Terry}

{pstd}
The display shows the log likelihood ({cmd:e(ll)}), maximum constrained
gradient ({cmd:e(gradient_max)}), Newton-system residual
({cmd:e(newton_residual)}), and linear-solve route ({cmd:e(linear_route)}).
Acceptance checks the likelihood first-order conditions, stability of
likelihood changes, and the Newton solve. A small Sorkin residual and a
small Bradley--Terry gradient certify different equations and have different
scales.

{pstd}
With {cmd:component(all)}, likelihoods are summed; iteration counts and
residual norms are maxima over component solves. {cmd:e(linear_route)}
records the final component's route, so it need not describe every solve.
{cmd:e(line_search_steps)} sums line-search reductions across components.
Unneeded method-specific scalars can be zero; they are not certificates
for the other method.

{pstd}
Numerical certificates concern computational accuracy. They are not
sampling standard errors, confidence intervals, or evidence that scores are
precisely estimated in the population. Version 0.1 supplies no inference,
{cmd:predict}, coefficient vector {cmd:e(b)}, or covariance matrix {cmd:e(V)}.

{marker results}
{title:Using generated variables}

{pstd}
The variables requested through {cmd:generate()}, {cmd:score()},
{cmd:percentile()} and {cmd:componentid()} are added to your current dataset.
Their names are stored in {cmd:e(rankvars)}, {cmd:e(scorevars)},
{cmd:e(percentilevars)} and {cmd:e(componentvars)}, respectively. Panel mode
stores one name per option; prepared-flow mode stores origin then destination.

{pstd}
For a panel estimated with {cmd:generate(firm_rank) score(firm_score)}, use:

{phang2}{cmd:. estat components}{p_end}
{phang2}{cmd:. estat convergence}{p_end}
{phang2}{cmd:. list firm firm_rank firm_score if firm_rank<=10}{p_end}
{phang2}{cmd:. save "panel_with_rankings.dta", replace}{p_end}

{pstd}
Save distinct names when comparing methods. Earlier generated variables
survive a subsequent estimate, but {cmd:e()} describes only the most recent
successful call. Use continuous scores for Pearson correlations with AKM.
On worker-year rows, repeated firm scores induce person-year weighting;
use one matched row per firm for an equal-firm comparison. The
{help ferank##examples:main help examples} illustrate both methods.

{pstd}
Rows outside the original {cmd:if}/{cmd:in} restrictions remain missing, even
if their firm was ranked. No out-of-sample attachment command is currently
provided. There is no {cmd:e(sample)}, {cmd:predict} or result frame.

{title:Also see}

{pstd}
{help ferank}, {help generate}, {help egen}, {help estat}{p_end}
