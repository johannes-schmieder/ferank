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
{help ferank_postestimation##results:Using the result frame}

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
({cmd:e(component)}), and the number of returned firms ({cmd:e(N_results)}).
The component count includes single-firm components, which cannot be
estimated. The display is a summary, not a table of every component or an
observation-level sample indicator.

{pstd}
{cmd:e(N_firms)} and {cmd:e(N_edges)} count firms and edges after flow
aggregation and {cmd:minflow()} filtering, but before component selection.
The result frame instead contains firms from selected estimable components,
with component-internal flows and degrees. To inspect separately estimated
groups after {cmd:component(all)}, sort that frame by {cmd:component_id} and
{cmd:rank}. Scores and percentiles from different components are not
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
gate. The signed firm-level residuals are in {cmd:fixed_point_residual}.

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
{title:Using the result frame}

{pstd}
The frame named in {cmd:e(result_frame)} contains firm IDs, component IDs,
scores, ranks and percentiles. Use frame commands to inspect or save it
without replacing the panel in memory:

{phang2}{cmd:. estat components}{p_end}
{phang2}{cmd:. estat convergence}{p_end}
{phang2}{cmd:. local ranking "`e(result_frame)'"}{p_end}
{phang2}{cmd:. frame `ranking': sort component_id rank}{p_end}
{phang2}{cmd:. frame `ranking': list firm_id score rank percentile if rank<=10}{p_end}
{phang2}{cmd:. frame `ranking': save "firm_rankings.dta", replace}{p_end}

{pstd}
The save command writes to your current working directory. Retained frames
survive a subsequent estimate, but {cmd:e()} always describes only the most
recent estimate. Retain distinct frames when comparing methods and match
by the original {cmd:firm_id}. The
{help ferank##examples:main help examples} show how to link the two frames.

{title:Also see}

{pstd}
{help ferank}, {help frames}, {help frlink}, {help frget}, {help estat}{p_end}
