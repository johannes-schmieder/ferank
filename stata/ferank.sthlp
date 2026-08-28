{smcl}
{* *! version 0.1.0 28aug2026}{...}
{vieweralsosee "ferank postestimation" "help ferank_postestimation"}{...}

{title:Title}

{pstd}
{cmd:ferank} {hline 2} firm rankings from directed worker flows

{title:Syntax}

{p 8 16 2}
{cmd:ferank} {it:origin destination} {ifin},
{cmd:method(sorkin|bradleyterry)}
[{cmd:flow(}{it:varname}{cmd:)} {it:options}]

{p 8 16 2}
{cmd:ferank} {it:firm} {ifin},
{cmd:worker(}{it:varname}{cmd:)} {cmd:time(}{it:varname}{cmd:)}
{cmd:method(sorkin|bradleyterry)} [{it:options}]

{p 8 16 2}{cmd:ferank, version}

{p 8 16 2}{cmd:ferank, selftest}

{synoptset 28 tabbed}
{synopthdr}
{synoptline}
{synopt:{cmd:method(}{it:method}{cmd:)}}required ranking method{p_end}
{synopt:{cmd:flow(}{it:varname}{cmd:)}}positive prepared-edge flow; default one{p_end}
{synopt:{cmd:maxgap(}{it:#}{cmd:)}}largest panel transition gap; default one{p_end}
{synopt:{cmd:component(largest|}{it:#}{cmd:|all)}}estimation component{p_end}
{synopt:{cmd:normalize(mean|weighted|reference)}}additive normalization{p_end}
{synopt:{cmd:normweight(}{it:varname}{cmd:)}}firm weight for weighted normalization{p_end}
{synopt:{cmd:reference(}{it:#}{cmd:)}}firm set to zero under reference normalization{p_end}
{synopt:{cmd:minflow(}{it:#}{cmd:)}}minimum aggregated directed flow{p_end}
{synopt:{cmd:tolerance(}{it:#}{cmd:)}}certificate tolerance; default 1e-10{p_end}
{synopt:{cmd:maxiter(}{it:#}{cmd:)}}outer iteration limit; default 20,000{p_end}
{synopt:{cmd:threads(}{it:#}{cmd:)}}deterministic native worker request{p_end}
{synopt:{cmd:lazy(}{it:#}{cmd:)}}Sorkin lazy-transition weight; default 0.5{p_end}
{synopt:{cmd:engine(plugin|reference)}}production or bounded dense engine{p_end}
{synopt:{cmd:frame(}{it:name}{cmd:)}}result frame; default {cmd:ferank_results}{p_end}
{synopt:{cmd:replace}}replace an existing result frame after success{p_end}
{synoptline}

{title:Description}

{pstd}
{cmd:ferank} constructs one canonical directed flow graph and estimates either
the Sorkin revealed-preference fixed point or a Bradley--Terry likelihood in
which each destination firm wins the observed origin-to-destination
comparison. Higher scores mean higher ranks.

{pstd}
Prepared-edge weights must be nonnegative and finite. Zero weights and
self-moves are excluded and counted. Duplicate directed pairs are aggregated
deterministically before {cmd:minflow()} is applied.

{pstd}
Panel mode requires one firm per worker-time. Duplicate worker-time rows are
errors. Missing firms break transition chains; same-firm observations are
continuations; and only different-firm consecutive observations within
{cmd:maxgap()} form unit moves.

{pstd}
Estimation requires a strongly connected positive-flow component. Components
are never silently joined or regularized. Results from separate components are
not comparable.

{title:Result frame}

{pstd}
The caller's data and order are unchanged. The result frame contains
{cmd:firm_id}, {cmd:method}, {cmd:component_id},
{cmd:in_estimation_component}, {cmd:score}, {cmd:rank}, {cmd:percentile},
{cmd:inflow}, {cmd:outflow}, {cmd:in_degree}, and {cmd:out_degree}. Sorkin also
fills {cmd:revealed_value_q}, {cmd:stationary_mass}, and
{cmd:fixed_point_residual}; those columns are missing after Bradley--Terry.

{title:Stored results}

{pstd}{cmd:ferank} stores the following in {cmd:e()}:

{synoptset 28 tabbed}
{synopt:{cmd:e(cmd)}}{cmd:ferank}{p_end}
{synopt:{cmd:e(method)}}ranking method{p_end}
{synopt:{cmd:e(input_mode)}}{cmd:edge} or {cmd:panel}{p_end}
{synopt:{cmd:e(result_frame)}}firm-level result frame{p_end}
{synopt:{cmd:e(N_input)}}marked input rows{p_end}
{synopt:{cmd:e(N_firms)}}canonical graph firms{p_end}
{synopt:{cmd:e(N_edges)}}canonical directed edges{p_end}
{synopt:{cmd:e(N_components)}}reported SCC count{p_end}
{synopt:{cmd:e(N_results)}}firms returned from selected components{p_end}
{synopt:{cmd:e(iterations)}}maximum component iteration count{p_end}
{synopt:{cmd:e(residual_max)}}Sorkin maximum original-equation residual{p_end}
{synopt:{cmd:e(ll)}}Bradley--Terry log likelihood{p_end}
{synopt:{cmd:e(gradient_max)}}Bradley--Terry constrained-gradient certificate{p_end}
{synopt:{cmd:e(convergence_certificate)}}{cmd:success} after accepted results{p_end}

{title:Examples}

{phang2}{cmd:. ferank origin destination, method(sorkin) flow(moves) frame(sr) replace}{p_end}
{phang2}{cmd:. estat convergence}{p_end}
{phang2}{cmd:. frame sr: list firm_id score rank}{p_end}

{phang2}{cmd:. ferank firm, worker(worker_id) time(year) method(bradleyterry) frame(bt) replace}{p_end}

{title:Scope}

{pstd}
Version 0.1 returns point rankings from worker flows. It does not estimate wage
fixed effects, structural employer values, offer shares, rents, amenities, or
statistical inference. There is no {cmd:predict} command.

{title:Author}

{pstd}Johannes F. Schmieder{p_end}
