{smcl}
{* *! version 0.1.0 30sep2026}{...}
{vieweralsosee "ferank postestimation" "help ferank_postestimation"}{...}
{.-}
help for {cmd:ferank} {right:(Johannes F. Schmieder)}
{.-}

{title:Title}

{pstd}
{cmd:ferank} {hline 2} Firm rankings from directed worker flows

{pstd}
{cmd:ferank} ranks firms using observed worker moves. It estimates either
Sorkin's flow-based revealed-preference score or a Bradley--Terry score,
in which the destination of a move wins a comparison with the origin.
Both methods use the same directed flow graph and return a separate
firm-level result frame. A larger score means a more highly ranked firm;
{bf:rank 1 is the highest rank}.

{pstd}
{help ferank##quickstart:Example} | {help ferank##syntax:Syntax} |
{help ferank##options:Main options} | {help ferank##sample:Flow sample} |
{help ferank##output:Reading results}

{pstd}
{help ferank##methods:Methods} | {help ferank##weighting:Weighting} |
{help ferank##advanced:Advanced options} | {help ferank##examples:More examples} |
{help ferank##stored:Stored results} | {help ferank##troubleshooting:Troubleshooting}

{marker quickstart}
{title:Start with an example}

{pstd}
The six rows below record moves among three firms. For example, four workers
move from firm 1 to firm 2, and one moves in the opposite direction.
Every firm can be reached from every other firm by following directed moves.
Estimate Sorkin scores and inspect the firm-level results:

{cmd}{...}
        preserve
{* example_start - edges}{...}
        clear
        input double(origin destination moves)
        1 2 4
        2 1 1
        2 3 3
        3 2 1
        3 1 2
        1 3 1
        end
        tempname ranking
        ferank origin destination, method(sorkin) flow(moves) ///
            frame(`ranking')
        estat convergence
        frame `ranking': sort rank
        frame `ranking': list firm_id score rank percentile, noobs
        frame drop `ranking'
{* example_end}{...}
        restore
{txt}{...}

{pstd}
{stata ferank_run edges using ferank.sthlp:Click to run this example}
(your data are restored and the temporary result frame is removed).
This is a small syntax example, not evidence about an empirical labor market.

{pstd}
With a worker-year panel, the basic command is
{cmd:ferank firm_id, worker(worker_id) time(year) method(sorkin)}.
The default permits transitions between observations at most one time unit
apart. The {help ferank##panel_example:panel example} explains missing firms
and gaps. {cmd:method()} is always required; it has no default.

{marker syntax}
{title:Syntax}

{pstd}Prepared moves or aggregated directed flows:

{p 8 16 2}
{cmd:ferank} {it:origin destination} [{help if}] [{help in}],
{cmd:method(}{it:method}{cmd:)}
[{cmd:flow(}{it:varname}{cmd:)} {it:options}]

{pstd}Worker-period panel:

{p 8 16 2}
{cmd:ferank} {it:firm} [{help if}] [{help in}],
{cmd:worker(}{it:varname}{cmd:)} {cmd:time(}{it:varname}{cmd:)}
{cmd:method(}{it:method}{cmd:)} [{it:options}]

{pstd}
{it:method} is {cmd:sorkin} or {cmd:bradleyterry}. Firm and worker identifiers
may be numeric or string. In edge mode, origin and destination must both be
numeric or both be string. Time, flow and normalization weights must be
numeric. Stata's {cmd:[fw=]}, {cmd:[aw=]}, {cmd:[pw=]} and {cmd:[iw=]} syntax
is not supported; use {cmd:flow()} for weighted prepared moves.

  {it:Main options}{col 42}Description
  {hline 76}
    {cmd:method(sorkin|bradleyterry)}{col 42}ranking method (required)
    {cmd:flow(}{it:varname}{cmd:)}{col 42}edge weight; default one per row
    {cmd:worker(}{it:varname}{cmd:)}{col 42}worker identifier in panel mode
    {cmd:time(}{it:varname}{cmd:)}{col 42}numeric time in panel mode
    {cmd:maxgap(}{it:#}{cmd:)}{col 42}largest allowed time gap; default 1
    {cmd:component(largest|}{it:#}{cmd:|all)}{col 42}component choice; default largest
    {cmd:normalize(mean|weighted|reference)}{col 42}score centering; default mean
    {cmd:normweight(}{it:varname}{cmd:)}{col 42}firm weights for weighted centering
    {cmd:reference(}{it:#}{cmd:)}{col 42}numeric firm ID set to score zero
    {cmd:frame(}{it:name}{cmd:)}{col 42}result frame; default ferank_results
    {cmd:replace}{col 42}replace result frame after success
  {hline 76}

{pstd}
Numerical controls and flow filtering are listed under
{help ferank##advanced:Advanced options}. Stata 18 or later and a compatible
compiled ferank plugin are required for both estimation engines.

{marker options}
{title:Main options}

{phang}
{cmd:method(sorkin)} estimates log revealed values from the directed flow
system. {cmd:method(bradleyterry)} estimates pairwise log-odds scores from
origin-to-destination wins. Choose according to the flow relationship you
want to describe; the methods need not produce identical rankings.
See {help ferank##methods:What the two methods estimate}.

{phang}
{cmd:flow()} supplies a nonnegative, finite weight for each prepared-edge
row. Positive integer and fractional weights are allowed. If omitted, each
row contributes one move. Duplicate directed pairs are summed before
filtering; zero-flow rows and self-moves contribute no comparison.
Missing firm IDs or missing/negative flows are errors, rather than silently
dropped complete cases. {cmd:flow()} cannot be used in panel mode.

{phang}
{cmd:worker()} and {cmd:time()} must be supplied together with exactly one
firm variable. There must be one observation per worker-time value in the
requested sample. Worker and time IDs must be nonmissing. A missing firm is
allowed and breaks the transition chain. The caller's rows are ordered
internally; sorting or {cmd:xtset} beforehand is unnecessary.

{phang}
{cmd:maxgap()}, default 1, is a positive, finite time difference, in the
units of {cmd:time()}. It applies only to panel mode. Consecutive years or
Stata quarterly dates are one unit apart; Stata daily dates measure days.
For irregular dates, choose the gap deliberately or construct an edge list.
Increasing the gap permits moves across unobserved periods; it does not
establish that there was no intervening nonemployment or other employer.

{phang}
{cmd:component(largest)}, the default, selects the estimable strongly
connected component with the most firms. Ties are resolved by internal flow,
then by the smallest firm ID. {cmd:component(}{it:#}{cmd:)} selects a component
by its deterministic number. {cmd:component(all)} estimates all estimable
components separately. An estimable component has at least two firms and
positive internal flow. Its scores and ranks are comparable only within that
component; there is no common ordering across separate components.
See {help ferank##sample:Which firms and moves are used?}.

{phang}
{cmd:normalize(mean)}, the default, subtracts the unweighted mean score
within each estimated component. {cmd:normalize(weighted)} instead uses
{cmd:normweight()}; weights must be nonnegative and finite, constant within
firm, and have a positive total in each selected component. In panel mode,
repeat the firm's weight on its observations. In edge mode, each row's
weight belongs to its {bf:origin} firm, and weights must be supplied for
every firm in the canonical graph. {cmd:normalize(reference)} sets the score
of the numeric firm ID in {cmd:reference()} to zero; that firm must belong
to every selected component, so use a single component for this normalization.
For string IDs, use mean or weighted centering, or encode IDs explicitly
before choosing a numeric reference. Centering shifts scores by a constant
and leaves ranks and fitted comparisons unchanged.

{phang}
{cmd:frame()} names the firm-level result frame, default
{cmd:ferank_results}. The caller's dataset and observation order stay
unchanged. {cmd:replace} permits replacement of an existing result frame
after successful estimation. Without it, an existing frame is an error.
Use distinct names when retaining both methods for comparison.

{marker sample}
{title:Which firms and moves are used? The flow sample}

{pstd}
{cmd:if} and {cmd:in} first select input rows. In edge mode, the command
removes zero flows and self-moves, sums duplicate origin-destination pairs,
applies {cmd:minflow()}, and constructs the directed graph. Firms that have
no surviving edge are absent from that graph.

{pstd}
In panel mode, moves are built using only the selected worker observations.
For each worker, a move is recorded when consecutive observations have
different nonmissing firms and their time difference is no greater than
{cmd:maxgap()}. Each move has unit weight. A missing-firm observation breaks
the chain even if a larger gap is allowed. An excessive gap also contributes
no move. Same-firm continuations contribute no edge. Dropping rows with
{cmd:if}/{cmd:in} changes which observations are consecutive; consider this
when setting {cmd:maxgap()}.

{pstd}
The command then finds strongly connected components: groups within which
every firm can reach every other firm by following directed moves.
An undirected connected graph alone is insufficient. One-way links between
components do not enter their separately estimated scores. No links are
added, and there is no smoothing or automatic component bridging. Firms
observed only among stayers have no flow comparison and receive no score.

{pstd}
The result frame contains only firms in the selected estimable components.
{cmd:e(N_firms)}, {cmd:e(N_edges)} and {cmd:e(N_components)} describe the
{bf:full canonical graph before component selection}; {cmd:e(N_results)}
counts returned firms. Frame inflows, outflows and degrees concern only
edges internal to each selected component. {cmd:estat components} displays
the component count, requested rule and result-firm count; it does not
provide a firm-by-firm exclusion map or a table of all components.

{pstd}
There is no observation-level {cmd:e(sample)} indicator. To attach scores
to your panel, match its firm ID to {cmd:firm_id} in the result frame.
Unmatched firms have no estimated score. Restricting to an AKM connected or
leave-out-connected sample does not by itself guarantee a directed strongly
connected flow sample.

{pstd}
The command does not automatically reproduce Sorkin's empirical sample
restrictions, quarterly direct EE definition, or structural adjustments.
Resolve concurrent jobs, dominant-job assignments, nonemployment spells,
recalls and spell-date rules before estimation. Use a prepared edge list
when the narrow worker-period contract does not describe your data.

{marker output}
{title:Reading the results}

{pstd}
The main display names the result frame, shows result firms alongside
canonical edges and components, and reports numerical success. Inspect
{cmd:estat convergence} and the frame to read the substantive results:

{phang2}{cmd:. estat components}{p_end}
{phang2}{cmd:. estat convergence}{p_end}
{phang2}{cmd:. frame ferank_results: sort rank}{p_end}
{phang2}{cmd:. frame ferank_results: list firm_id score rank percentile if rank<=10}{p_end}

  {it:Result-frame variable}{col 35}Meaning
  {hline 76}
    {cmd:firm_id}{col 35}original numeric or string firm identifier
    {cmd:method}{col 35}sorkin or bradleyterry
    {cmd:component_id}{col 35}component number in the canonical graph
    {cmd:in_estimation_component}{col 35}one for every returned row
    {cmd:score}{col 35}normalized method-specific score
    {cmd:rank}{col 35}descending within-component midrank; 1 best
    {cmd:percentile}{col 35}within-component rank percentile, 0 to 100
    {cmd:inflow}, {cmd:outflow}{col 35}internal directed flow totals
    {cmd:in_degree}, {cmd:out_degree}{col 35}distinct internal incoming/outgoing neighbors
    {cmd:revealed_value_q}{col 35}Sorkin value before score centering
    {cmd:stationary_mass}{col 35}Sorkin stationary probability mass
    {cmd:fixed_point_residual}{col 35}Sorkin signed stationary-equation residual
  {hline 76}

{pstd}
The last three variables are missing after Bradley--Terry. Exact score ties
receive their average rank. With J firms in a component,
{cmd:percentile = 100*(J-rank)/(J-1)}: the unique highest-scoring firm has
percentile 100, and the unique lowest-scoring firm has percentile 0.
These are {bf:equal-firm rank percentiles}, regardless of normalization.

{marker methods}
{title:What the two methods estimate}

{pstd}
Let M[i,j] be the observed flow from origin j to destination i, and let s[j]
be total outflow from j within the selected component. Sorkin's flow value q
solves {cmd:M*q = diag(s)*q}. Equivalently, with
{cmd:P = M*diag(s)^(-1)}, stationary mass pi satisfies
{cmd:P*pi = pi} and {cmd:sum(pi) = 1}, and {cmd:q[j] = pi[j]/s[j]}.
The reported {cmd:score} is {cmd:ln(q)} after the requested centering.
{cmd:revealed_value_q} retains the stationary-mass scaling, so it need not
equal {cmd:exp(score)} after centering. A high stationary mass alone is not
the revealed value: the method also accounts for the firm's outflow.

{pstd}
Bradley--Terry treats the destination as the winner in each observed move.
For a compared pair, the fitted probability that i wins against j is
{cmd:invlogit(score[i]-score[j])}. The score difference is the fitted
log odds for that pair. This is a pairwise flow model, rather than a
prediction of an individual worker's next employer or an unconditional
firm market share. Sorkin uses propagation through the whole flow system;
Bradley--Terry uses pairwise win frequencies. Their scores have different
cardinal interpretations.

{pstd}
Both methods return descriptive point scores from flows. Neither estimates
an AKM wage effect, a causal employer effect, a structural employer utility,
an amenity, rent, or a compensating-wage decomposition. There are no sampling
standard errors or confidence intervals, {cmd:e(b)}, {cmd:e(V)}, or
{cmd:predict} after {cmd:ferank}. A numerical convergence certificate
measures computational accuracy, not statistical precision.

{marker weighting}
{title:Flow weights, score centering and comparison weights}

{pstd}
{cmd:flow()} changes the directed comparisons and may change estimated
scores and ranks. {cmd:normweight()} changes only the additive score origin.
It does not employment-weight the likelihood, flow graph, ranks or
percentiles. Person-year weighting of a correlation with AKM effects, a
binned scatterplot, or a percentile distribution is a separate calculation
on matched firm-level results. Use the same firms and explicit comparison
weights for both methods. The Veneto benchmark under {cmd:bench/} illustrates
these distinctions; the command itself does not impose a firm-size filter.

{marker postestimation}
{title:Postestimation display}

  {it:Command}{col 35}What it shows
  {hline 76}
    {cmd:estat components}{col 35}component count, rule and returned firms
    {cmd:estat convergence}{col 35}method-specific numerical certificate
  {hline 76}

{pstd}
See {help ferank_postestimation} for the certificate definitions and stored
diagnostics. These commands report the most recent successful estimation;
when fitting both methods, inspect each before running the next command.

{marker advanced}
{title:Advanced options}

{pstd}
Most applications can use the numerical defaults. Changing flow filtering
changes the graph and estimand; changing a numerical control does not repair
an unidentified graph.

  {it:Option}{col 35}Description
  {hline 76}
    {cmd:minflow(}{it:#}{cmd:)}{col 35}minimum directed edge total; default 0
    {cmd:tolerance(}{it:#}{cmd:)}{col 35}positive certificate tolerance; default 1e-10
    {cmd:maxiter(}{it:#}{cmd:)}{col 35}positive iteration limit; default 20,000
    {cmd:threads(}{it:#}{cmd:)}{col 35}native worker request; default 0 uses 1
    {cmd:lazy(}{it:#}{cmd:)}{col 35}Sorkin transition weight; default 0.5
    {cmd:engine(plugin|reference)}{col 35}estimation engine; default plugin
    {cmd:verbose}{col 35}accepted; currently adds no display output
  {hline 76}

{phang}
{cmd:minflow()} retains canonical directed edges whose aggregated flow is
at least the specified nonnegative, finite threshold. Filtering occurs
before component selection and may split the graph or remove firms. With
the default zero, all positive canonical flows are eligible.

{phang}
{cmd:tolerance()} controls method-specific numerical acceptance.
Production Sorkin requires both maximum absolute and L1 residuals of
{cmd:P*pi-pi} to meet the tolerance, plus agreement of scores from an
alternative starting mass. Bradley--Terry checks the constrained likelihood
gradient, likelihood stability and the Newton-system solve.
The residual quantities have different scales; compare them to their own
method's criteria. {cmd:maxiter()} bounds each component's iterative solve.
An exhausted or uncertified solve returns an error rather than a partial
ranking. The reference Sorkin engine solves a dense system directly.

{phang}
{cmd:threads()} is a nonnegative integer request for native worker threads;
zero currently selects one. Actual use is bounded by the work available,
and the dense reference engine uses one thread. This option is separate
from Stata/MP's {cmd:set processors}. Thread count can affect runtime;
successful results must satisfy the same numerical certificates.

{phang}
{cmd:lazy()} must lie in (0,1]. Production Sorkin iterates on
{cmd:(1-lazy)*I + lazy*P}. The default 0.5 avoids oscillation in periodic
graphs while preserving the stationary solution. A value of 1 removes
laziness and can fail to converge on periodic graphs. It has no effect on
Bradley--Terry or the direct reference Sorkin solve.

{phang}
{cmd:engine(reference)} uses independent dense reference solvers, limited
to 2,048 firms per selected component. It is intended for small validation
examples, not a fallback for large data. It still requires the compiled
plugin. Its direct Sorkin certificate uses the reference engine's scaled
residual gate; iteration counts and numerical routes can differ from the
production engine. No automatic engine substitution occurs after failure.

{pstd}
{cmd:ferank, version} reports package/plugin version information;
{cmd:ferank, selftest} checks the plugin interface. These are standalone
commands and clear prior {cmd:e()} results. A selftest is an installation
check, not a data-specific convergence check.

{marker examples}
{title:More examples}

{marker panel_example}
{dlgtab:Example 2: An annual panel with a missing employer and a gap}

{pstd}
There are two valid moves, 10 to 20 and 20 to 10. Worker 1's missing employer
breaks the chain; worker 3's two-year gap contributes no move at the default
{cmd:maxgap(1)}. Counts refer to transitions formed before component selection.

{cmd}{...}
        preserve
{* example_start - panel}{...}
        clear
        input double(worker_id year firm_id)
        1 1996 10
        1 1997 20
        1 1998 .
        1 1999 10
        2 1996 20
        2 1997 10
        3 1996 10
        3 1998 20
        end
        tempname ranking
        ferank firm_id, worker(worker_id) time(year) ///
            method(bradleyterry) frame(`ranking')
        display "Moves: " e(valid_moves) "; gap breaks: " e(gap_breaks)
        display "Missing-firm breaks: " e(missing_firm_breaks)
        frame `ranking': list firm_id score rank, noobs
        frame drop `ranking'
{* example_end}{...}
        restore
{txt}{...}
{pstd}{stata ferank_run panel using ferank.sthlp:Click to run}{p_end}

{dlgtab:Example 3: Compare both methods on the same flows}

{pstd}
Keep separate result frames and link them by the original firm ID. This
example also shows string identifiers and fractional prepared flows.

{cmd}{...}
        preserve
{* example_start - compare}{...}
        clear
        input str1 origin str1 destination double moves
        "a" "b" 4.5
        "b" "a" 1
        "b" "c" 3
        "c" "b" 1
        "c" "a" 2
        "a" "c" 1
        end
        tempname sr bt
        ferank origin destination, method(sorkin) flow(moves) frame(`sr')
        ferank origin destination, method(bradleyterry) flow(moves) ///
            frame(`bt')
        frame `sr': frlink 1:1 firm_id, frame(`bt') generate(bt_link)
        frame `sr': frget bt_score=score bt_rank=rank, from(bt_link)
        frame `sr': list firm_id score bt_score rank bt_rank, noobs
        frame drop `sr' `bt'
{* example_end}{...}
        restore
{txt}{...}
{pstd}{stata ferank_run compare using ferank.sthlp:Click to run}{p_end}

{dlgtab:Example 4: Separate strongly connected components}

{pstd}
The two components have no path between them. {cmd:component(all)} returns
both, with a separate normalization and rank distribution for each. Sorting
all scores together would invent a comparison that the data do not identify.

{cmd}{...}
        preserve
{* example_start - components}{...}
        clear
        input double(origin destination moves)
        1 2 3
        2 1 1
        10 11 2
        11 10 1
        end
        tempname ranking
        ferank origin destination, method(sorkin) flow(moves) ///
            component(all) frame(`ranking')
        estat components
        frame `ranking': sort component_id rank
        frame `ranking': list component_id firm_id score rank, noobs ///
            sepby(component_id)
        frame drop `ranking'
{* example_end}{...}
        restore
{txt}{...}
{pstd}{stata ferank_run components using ferank.sthlp:Click to run}{p_end}

{dlgtab:Example 5: Employment-weighted score centering}

{pstd}
Weights below are firm-level person-year totals repeated on the origin's
rows. The weighted mean score is zero. Moves retain their original weights
and the command's percentiles remain equal-firm percentiles.

{cmd}{...}
        preserve
{* example_start - normalization}{...}
        clear
        input double(origin destination moves person_years)
        1 2 4 200
        2 1 1 100
        2 3 3 100
        3 2 1 150
        3 1 2 150
        1 3 1 200
        end
        tempname ranking
        ferank origin destination, method(sorkin) flow(moves) ///
            normalize(weighted) normweight(person_years) frame(`ranking')
        frame `ranking': generate double person_years = ///
            cond(firm_id==1, 200, cond(firm_id==2, 100, 150))
        frame `ranking': summarize score [aw=person_years]
        frame drop `ranking'
{* example_end}{...}
        restore
{txt}{...}
{pstd}{stata ferank_run normalization using ferank.sthlp:Click to run}{p_end}

{marker stored}
{title:Stored results}

{pstd}
{cmd:ferank} is {cmd:eclass}, with firm-level point estimates in the result
frame rather than a coefficient vector. Following successful estimation:

  {it:Graph and panel counts}{col 35}Meaning
  {hline 76}
    {cmd:e(N_input)}{col 35}marked input rows before flow construction
    {cmd:e(N_firms)}{col 35}firms in the full canonical graph
    {cmd:e(N_edges)}{col 35}canonical edges before component selection
    {cmd:e(N_components)}{col 35}all SCCs, including single-firm SCCs
    {cmd:e(N_results)}{col 35}firms returned from selected components
    {cmd:e(valid_moves)}{col 35}constructed panel moves before filtering
    {cmd:e(gap_breaks)}{col 35}panel transitions exceeding maxgap()
    {cmd:e(missing_firm_breaks)}{col 35}panel rows with a missing firm
    {cmd:e(same_firm_continuations)}{col 35}same-firm transitions within maxgap()
  {hline 76}

{pstd}
The last four scalars are panel diagnostics and are zero in edge mode.
They do not count only the selected component.

  {it:Numerical and timing scalars}{col 35}Meaning
  {hline 76}
    {cmd:e(iterations)}{col 35}maximum iterations over selected components
    {cmd:e(residual_max)}{col 35}maximum component Sorkin absolute residual
    {cmd:e(residual_l1)}{col 35}maximum component Sorkin L1 residual
    {cmd:e(ll)}{col 35}summed component log likelihoods
    {cmd:e(gradient_max)}{col 35}maximum constrained-gradient certificate
    {cmd:e(newton_residual)}{col 35}maximum Newton-system residual
    {cmd:e(line_search_steps)}{col 35}summed line-search reductions
    {cmd:e(threads)}{col 35}maximum effective native thread count
    {cmd:e(time_input_graph)}{col 35}native input, graph and SCC seconds
    {cmd:e(time_solve_rank)}{col 35}native estimation and ranking seconds
    {cmd:e(time_store)}{col 35}plugin result-publication seconds
    {cmd:e(time_total)}{col 35}native/plugin elapsed seconds
  {hline 76}

{pstd}
Method-inapplicable numerical scalars may be zero; zero does not establish
a certificate for another method. Native timings exclude Stata's preparation
and final frame publication, so use an external Stata timer for complete
command runtime. With {cmd:component(all)}, maximum diagnostics and summed
likelihoods/line-search counts summarize multiple separate solves.

  {it:Macros}{col 35}Meaning
  {hline 76}
    {cmd:e(cmd)}{col 35}ferank
    {cmd:e(cmdline)}{col 35}estimation command
    {cmd:e(method)}{col 35}sorkin or bradleyterry
    {cmd:e(input_mode)}{col 35}edge or panel
    {cmd:e(component)}{col 35}requested component rule
    {cmd:e(normalization)}{col 35}requested score centering
    {cmd:e(engine)}{col 35}plugin or reference
    {cmd:e(result_frame)}{col 35}name of firm-level result frame
    {cmd:e(convergence_certificate)}{col 35}success for an accepted estimate
    {cmd:e(linear_route)}{col 35}Bradley--Terry linear-solve route
    {cmd:e(estat_cmd)}{col 35}ferank_estat
  {hline 76}

{pstd}
Use {cmd:ereturn list} to inspect the stored record immediately after
estimation. Each new estimate replaces {cmd:e()}, even when earlier result
frames are retained. After a failed command, inspect its error rather than
treating a previous estimate in {cmd:e()} as the failed command's result.

{marker troubleshooting}
{title:If estimation fails}

{phang}
{bf:No usable moves or component, r(2000):} Check the requested sample,
time units, missing employers, directed connectivity and {cmd:minflow()}.
With only one-way comparisons, finite scores are not identified. Pooling
unrelated firms or raising iteration limits does not create identifying flows.

{phang}
{bf:Invalid data, r(459):} Check worker-time uniqueness, nonmissing
identifiers and numeric times, nonnegative finite flows, and firm-constant
normalization weights. Prepare concurrent employment or spell rules upstream.

{phang}
{bf:No convergence, r(430):} Read the reported residual or solver failure.
Weakly connected flow graphs can converge slowly. For Sorkin, retain the
default laziness and consider a larger {cmd:maxiter()} after checking the
graph. Relaxing tolerance reduces numerical accuracy; it is not an
identification or reliability correction.

{phang}
{bf:Existing result frame, r(110):} Choose another {cmd:frame()} or request
{cmd:replace}. An unsuccessful solve does not publish a partial result frame
or replace the target frame.

{phang}
{bf:Plugin or installation failure:} Run {cmd:ferank, version} and
{cmd:ferank, selftest}; confirm that Stata finds a plugin compatible with the
installed ado files and operating system. The reference engine also needs
the plugin. Include the exact command, Stata version, error, plugin version
and a small reproducible example when reporting a problem.

{marker references}
{title:References and further reading}

{pstd}
Sorkin, Isaac. 2018. "Ranking Firms Using Revealed Preference."
{it:Quarterly Journal of Economics} 133(3): 1331-1393.
{browse "https://doi.org/10.1093/qje/qjy001":doi:10.1093/qje/qjy001}.
The command estimates the raw flow-based score, not the paper's full
structural employer-value or compensating-differential decomposition.

{pstd}
Bradley, Ralph Allan, and Milton E. Terry. 1952. "Rank Analysis of Incomplete
Block Designs: I. The Method of Paired Comparisons."
{it:Biometrika} 39(3-4): 324-345.
{browse "https://doi.org/10.1093/biomet/39.3-4.324":doi:10.1093/biomet/39.3-4.324}.

{pstd}
{browse "https://github.com/johannes-schmieder/ferank/blob/main/docs/methods.md":Method and input-contract documentation}
provides the equations and numerical details.

{marker author}
{title:Author}

{pstd}
Johannes F. Schmieder, Boston University.
{browse "mailto:johannes@bu.edu":johannes@bu.edu}

{pstd}
Version 0.1.0 is alpha software. Code is GPL-3.0-only.

{title:Also see}

{pstd}
{help ferank_postestimation}, {help frames}, {help frlink}, {help frget},
{help estat}, {help timer}{p_end}
