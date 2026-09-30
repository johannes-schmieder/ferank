/* Report-only companion: no estimation is repeated when editing the report. */
version 19.0
args out
timer clear 93
timer on 93
local sample_profile "full"
local source_rows 5163428
local source_firms 86647
local size_eligible_rows 5163428
local size_eligible_firms 86647
local minimum_nonsingleton 0
local sample_preparation_seconds 0
local selection_loads_ferank 0
use `"`out'/run_metadata.dta"', clear
foreach variable of varlist _all {
    local `variable' = `variable'[1]
}
local obs_fmt : display %12.0fc `panel_rows'
local workers_fmt : display %12.0fc `panel_workers'
local firms_fmt : display %12.0fc `panel_firms'
local matches_fmt : display %12.0fc `panel_matches'
local moves_fmt : display %12.0fc `adjacent_moves'
local gaps_fmt : display %12.0fc `panel_gap_breaks'
local import_fmt : display %9.2f `import_seconds'
local validation_fmt : display %9.2f `validation_seconds'
local preparation_fmt : display %9.2f `sample_preparation_seconds'
local source_rows_fmt : display %12.0fc `source_rows'
local source_firms_fmt : display %12.0fc `source_firms'
local eligible_rows_fmt : display %12.0fc `size_eligible_rows'
local eligible_firms_fmt : display %12.0fc `size_eligible_firms'
local sample_title "Full prepared Veneto sample"
if "`sample_profile'"=="sorkin" local sample_title "Sorkin-style Veneto sample"

/* Both ranking methods must select exactly the same directed component. */
use `"`out'/sorkin_baseline.dta"', clear
rename score sorkin_score
rename rank sorkin_rank
rename percentile sorkin_percentile
keep firm sorkin_score sorkin_rank sorkin_percentile inflow outflow
tempfile sorkin
save `sorkin'
use `"`out'/bradleyterry_baseline.dta"', clear
rename score bt_score
rename rank bt_rank
rename percentile bt_percentile
keep firm bt_score bt_rank bt_percentile
merge 1:1 firm using `sorkin', assert(match) nogen
merge 1:1 firm using `"`out'/akm_baseline.dta"', ///
    keepusing(score employment) assert(match using) keep(match) nogen
rename score akm_effect
assert employment>0 & employment==floor(employment)
quietly summarize akm_effect [fw=employment], meanonly
replace akm_effect = akm_effect-r(mean)
local common = _N
local common_fmt : display %12.0fc `common'
quietly summarize employment, meanonly
local common_observations = r(sum)
local common_observations_fmt : display %12.0fc `common_observations'
if "`sample_profile'"=="sorkin" assert `common'==`panel_firms' & `common_observations'==`panel_rows'
rename sorkin_percentile firm_sorkin_percentile
rename bt_percentile firm_bt_percentile
/* Frequency-weight ranks are CDF midpoints, equivalent to expanded worker-years.
   Native package ranks remain unaltered in each saved estimation baseline. */
foreach object in akm sorkin bt {
    local value = cond("`object'"=="akm","akm_effect","`object'_score")
    egen double firm_`object'_midrank = rank(`value')
    sort `value' firm
    egen double tied_weight = total(employment), by(`value')
    gen double cumulative_weight = sum(employment)
    by `value': gen double `object'_midrank = cumulative_weight[_N]-tied_weight/2
    gen double `object'_percentile = 100*`object'_midrank/`common_observations'
    drop tied_weight cumulative_weight
}
assert !missing(akm_effect,sorkin_score,bt_score,sorkin_percentile,bt_percentile)
assert inrange(sorkin_percentile,0,100) & inrange(bt_percentile,0,100)
local coverage : display %5.1f (100*`common'/`size_eligible_firms')
quietly summarize employment if sorkin_percentile>=90 & bt_percentile>=90, meanonly
local top_overlap = r(sum)
quietly summarize employment if sorkin_percentile>=90, meanonly
local top_s = r(sum)
local top_overlap_pct : display %5.1f (100*`top_overlap'/`top_s')
tempname correlation_records
postfile `correlation_records' str24 comparison str16 weighting double pearson double spearman ///
    using `"`out'/correlations.dta"', replace
foreach pair in s bt flow {
    local x = cond("`pair'"=="flow","sorkin_score","akm_effect")
    local y = cond("`pair'"=="s","sorkin_score","bt_score")
    local xr = cond("`pair'"=="flow","sorkin_midrank","akm_midrank")
    local yr = cond("`pair'"=="s","sorkin_midrank","bt_midrank")
    local label = cond("`pair'"=="s","akm_sorkin",cond("`pair'"=="bt","akm_bradleyterry","sorkin_bradleyterry"))
    quietly correlate `x' `y' [fw=employment]
    local pearson_`pair' = r(rho)
    quietly correlate `xr' `yr' [fw=employment]
    local spearman_`pair' = r(rho)
    post `correlation_records' ("`label'") ("person_years") (`pearson_`pair'') (`spearman_`pair'')
    quietly correlate `x' `y'
    local equal_pearson = r(rho)
    quietly correlate firm_`xr' firm_`yr'
    local equal_spearman = r(rho)
    post `correlation_records' ("`label'") ("equal_firms") (`equal_pearson') (`equal_spearman')
}
postclose `correlation_records'
preserve
use `"`out'/correlations.dta"', clear
export delimited using `"`out'/correlations.csv"', replace
restore
foreach quantity in pearson_s pearson_bt pearson_flow spearman_s spearman_bt spearman_flow {
    local `quantity'_fmt : display %6.3f ``quantity''
}
quietly save `"`out'/firm_comparison.dta"', replace
/* Weighted quantile bins preserve whole firms and use weighted means. */
xtile akm_bin = akm_effect [fw=employment], nq(20)
egen double bin_person_years = total(employment), by(akm_bin)
foreach variable in akm_effect sorkin_percentile bt_percentile sorkin_score bt_score {
    gen double weighted_value = employment*`variable'
    egen double bin_`variable' = total(weighted_value), by(akm_bin)
    replace bin_`variable' = bin_`variable'/bin_person_years
    drop weighted_value
}
egen byte bin_tag = tag(akm_bin)
bysort akm_bin: gen long bin_firms = _N
quietly count if bin_tag
assert r(N)==20
preserve
keep if bin_tag
keep akm_bin bin_firms bin_person_years bin_akm_effect bin_sorkin_percentile bin_bt_percentile bin_sorkin_score bin_bt_score
sort akm_bin
quietly summarize bin_firms, meanonly
assert r(sum)==`common'
local bin_min_fmt : display %9.0fc r(min)
local bin_max_fmt : display %9.0fc r(max)
quietly summarize bin_person_years, meanonly
assert r(sum)==`common_observations'
local bin_weight_min_fmt : display %12.0fc r(min)
local bin_weight_max_fmt : display %12.0fc r(max)
quietly save `"`out'/binned_scatter_data.dta"', replace
export delimited using `"`out'/binned_scatter_data.csv"', replace
restore
local cpu_model "not recorded"
local memory_gib "not recorded"
capture confirm file `"`out'/hardware.txt"'
if !_rc {
    tempname hardware
    file open `hardware' using `"`out'/hardware.txt"', read text
    file read `hardware' cpu_model
    file read `hardware' memory_gib
    file close `hardware'
}
local report `"`out'/veneto_benchmark.tex"'
latexlog `report': open, replace ///
    geometry(lmargin=2.3cm,rmargin=2.3cm,tmargin=2.0cm,bmargin=2.0cm,marginparwidth=0pt) ///
    predocopen(\author{}\usepackage{lmodern,amsmath,microtype}\captionsetup{font=small,labelfont=bf}\setlength{\parindent}{0pt}\setlength{\parskip}{5pt})
latexlog `report': title "Firm rankings: `sample_title'"
latexlog `report': writeln "\begin{center}\large AKM wage effects, Sorkin, and Bradley--Terry\\\\[3pt]\normalsize Private benchmark --- `run_date'\end{center}"
latexlog `report': writeln "\textbf{Sample.} `obs_fmt' worker-year observations, `workers_fmt' workers and `firms_fmt' firms, 1996--2001. The selected directed strongly connected component has `common_fmt' firms (`coverage'\% of size-eligible firms), representing `common_observations_fmt' person-years.\par"
latexlog `report': writeln "\textbf{Comparison.} On the common firm sample, the Spearman correlation of AKM effects with Sorkin is `spearman_s_fmt'; with Bradley--Terry it is `spearman_bt_fmt'. The two flow rankings correlate at `spearman_flow_fmt'. Correlations, percentiles and bin means use firm person-year weights. These are different economic objects: an AKM wage premium and rankings from observed annual employer changes.\par"
if "`sample_profile'"=="sorkin" {
    latexlog `report': writeln "\textbf{Restriction.} Start from `source_rows_fmt' observations and `source_firms_fmt' firms. Retain firms with at least 90 person-years whose worker is observed again later in the original panel (`eligible_firms_fmt' firms; `eligible_rows_fmt' rows), then select the largest directed component. All three estimators are refitted on that common firm sample, retaining terminal observations for AKM and person-year weights.\par"
}
latexlog `report': section "Complete-command timings"
latexlog `report': writeln "The stopwatch starts immediately before the public estimation command and stops after it returns. AKM includes recovery of the firm effects and residuals; ferank includes full panel-to-flow construction and publication of its result frame. Import, validation, sample selection, output checks, merging, plots and LaTeX compilation are excluded. Repetition 0 is reported separately; repetitions 1--`measured_repetitions' rotate estimator order and determine the medians.\par"
preserve
use `"`out'/timings.dta"', clear
assert rc==0
count
local thread_settings : word count `native_threads'
local expected = 3*(`measured_repetitions'+1)*`thread_settings'
assert _N == `expected'
tempfile allcalls initial medians
save `allcalls'
keep if repetition==0
keep method threads wall_seconds
rename wall_seconds initial_seconds
save `initial'
use `allcalls', clear
keep if repetition>0
collapse (median) median_seconds=wall_seconds input_seconds solve_seconds store_seconds ///
    native_seconds iterations residual_max residual_l1 gradient_max newton_residual ///
    (min) min_seconds=wall_seconds (max) max_seconds=wall_seconds ///
    (count) repetitions=wall_seconds, by(method threads)
merge 1:1 method threads using `initial', assert(match) nogen
gen byte method_order = cond(method=="akm",1,cond(method=="sorkin",2,3))
sort threads method_order
save `medians'
quietly save `"`out'/timing_summary.dta"', replace
export delimited using `"`out'/timing_summary.csv"', replace
latexlog `report': writeln "\begin{table}[H]\centering\small\caption{Wall-clock seconds per complete estimation command}\begin{tabular}{lrrrrr}\toprule Method & Threads & Initial & Median & Minimum & Maximum\\\\\midrule"
forvalues row=1/`=_N' {
    local method_name = cond(method[`row']=="akm","AKM (fereg)",cond(method[`row']=="sorkin","Sorkin","Bradley--Terry"))
    foreach field in initial_seconds median_seconds min_seconds max_seconds {
        local `field'_fmt : display %8.2f `field'[`row']
    }
    local nt = threads[`row']
    latexlog `report': writeln "`method_name' & `nt' & `initial_seconds_fmt' & `median_seconds_fmt' & `min_seconds_fmt' & `max_seconds_fmt' \\\\"
}
latexlog `report': writeln "\bottomrule\end{tabular}\end{table}"
latexlog `report': writeln "\footnotesize Initial means the first call at each thread setting; in the restricted profile, ferank is already loaded by the untimed component-selection call. Other settings reuse the process. Medians use `measured_repetitions' calls each. CSV import: `import_fmt' seconds; input validation: `validation_fmt' seconds; sample restriction/component selection and descriptive preparation: `preparation_fmt' seconds. Thread counts are native requests. Stata/MP uses `stata_processors' licensed processors.\normalsize"
restore

latexlog `report': writeln "\clearpage"
latexlog `report': section "AKM effects and flow ranks"
latexlog `report': writeln "Each translucent point is one of the `common_fmt' common firms, with marker size scaled by person-years. The orange line joins person-year-weighted means in 20 weighted AKM quantile bins. AKM effects are centered at their person-year-weighted mean. Percentiles use the person-year distribution of flow scores. Every selected firm is shown.\par"
foreach method in sorkin bt {
    local name = cond("`method'"=="sorkin","Sorkin","Bradley-Terry")
    twoway (scatter `method'_percentile akm_effect [fw=employment], msymbol(o) mcolor(navy%12)) ///
        (connected bin_`method'_percentile bin_akm_effect if bin_tag, sort ///
            mcolor(orange_red) lcolor(orange_red) msize(small) lwidth(medthick)), ///
        xtitle("AKM firm wage effect (log points)") ytitle("`name' rank percentile") ///
        ylabel(0(20)100, angle(horizontal)) xlabel(,format(%5.1f)) ///
        legend(off) graphregion(color(white)) plotregion(color(white)) ///
        xsize(7) ysize(3.35) name(rank_`method',replace)
    /* High-resolution raster avoids a large PDF containing thousands of weighted vector markers. */
    graph export `"`out'/figures/akm_`method'_rank.png"', width(2600) replace
    latexlog `report': writeln "\begin{figure}[H]\centering\includegraphics[width=.96\textwidth]{figures/akm_`method'_rank.png}\caption{AKM wage effects and `name' rank percentiles}\end{figure}"
}
latexlog `report': writeln "\clearpage"
latexlog `report': section "Scores and agreement"
latexlog `report': writeln "Scores retain cardinal information that rank percentiles discard. Sorkin reports the normalized logarithm of its flow value; Bradley--Terry reports a normalized pairwise-choice score. Differences in scale and dispersion do not measure differences in wages.\par"
foreach method in sorkin bt {
    local name = cond("`method'"=="sorkin","Sorkin","Bradley-Terry")
    twoway (scatter `method'_score akm_effect [fw=employment], msymbol(o) mcolor(navy%12)) ///
        (connected bin_`method'_score bin_akm_effect if bin_tag, sort ///
            mcolor(orange_red) lcolor(orange_red) msize(small) lwidth(medthick)), ///
        xtitle("AKM firm wage effect (log points)") ytitle("`name' score") ///
        ylabel(,angle(horizontal)) xlabel(,format(%5.1f)) legend(off) ///
        graphregion(color(white)) plotregion(color(white)) xsize(7) ysize(2.65)
    graph export `"`out'/figures/akm_`method'_score.png"', width(2600) replace
    latexlog `report': writeln "\begin{figure}[H]\centering\includegraphics[width=.87\textwidth]{figures/akm_`method'_score.png}\caption{AKM wage effects and `name' scores}\end{figure}"
}
latexlog `report': writeln "\begin{table}[H]\centering\small\caption{Person-year-weighted correlations on the common component}\begin{tabular}{lrr}\toprule Comparison & Pearson (scores) & Spearman\\\\\midrule"
latexlog `report': writeln "AKM and Sorkin & `pearson_s_fmt' & `spearman_s_fmt' \\\\"
latexlog `report': writeln "AKM and Bradley--Terry & `pearson_bt_fmt' & `spearman_bt_fmt' \\\\"
latexlog `report': writeln "Sorkin and Bradley--Terry & `pearson_flow_fmt' & `spearman_flow_fmt' \\\\\bottomrule\end{tabular}\end{table}"
latexlog `report': writeln "The top-decile overlap is `top_overlap_pct'\% of the person-years in Sorkin's top decile. Weighted Spearman is the weighted correlation of person-year CDF midranks. For comparison, Sorkin (2018), Table II, panel E reports 0.400 Pearson and 0.427 Spearman for the unadjusted EE-flow value and AKM effects in US LEHD. The public replication release omits the final-table rank routine; Pearson provides the unambiguous weight-matched comparison.\par"

latexlog `report': writeln "\clearpage"
latexlog `report': section "Binned scatterplots: rank percentiles"
latexlog `report': writeln "Each point is a person-year-weighted mean in one of 20 weighted AKM quantile bins. Bins contain `bin_weight_min_fmt'--`bin_weight_max_fmt' person-years and `bin_min_fmt'--`bin_max_fmt' firms; whole firms are preserved at quantile boundaries. The line joins descriptive means. All selected firms contribute their person-year weights, and axes show the bin-mean ranges.\par"
foreach method in sorkin bt {
    local name = cond("`method'"=="sorkin","Sorkin","Bradley-Terry")
    twoway connected bin_`method'_percentile bin_akm_effect if bin_tag, sort ///
        msymbol(O) msize(medsmall) mcolor(navy) lcolor(navy) lwidth(medthin) ///
        xtitle("Mean AKM firm wage effect (log points)") ///
        ytitle("Mean `name' rank percentile") ///
        ylabel(,angle(horizontal) format(%5.1f)) xlabel(,format(%5.2f)) ///
        legend(off) graphregion(color(white)) plotregion(color(white)) ///
        xsize(7) ysize(3.35) name(binned_rank_`method',replace)
    graph export `"`out'/figures/akm_`method'_rank_binned.pdf"', replace
    latexlog `report': writeln "\begin{figure}[H]\centering\includegraphics[width=.96\textwidth]{figures/akm_`method'_rank_binned.pdf}\caption{Binned AKM wage effects and `name' rank percentiles}\end{figure}"
}
latexlog `report': writeln "\clearpage"
latexlog `report': section "Binned scatterplots: scores"
latexlog `report': writeln "These panels use the same 20 weighted AKM quantile bins and person-year weights as the preceding page. Points show mean cardinal scores rather than rank percentiles. Sorkin and Bradley--Terry use different score scales; each vertical axis is adapted to its own bin means. The original firm-level figures retain the full dispersion and extreme observations.\par"
foreach method in sorkin bt {
    local name = cond("`method'"=="sorkin","Sorkin","Bradley-Terry")
    twoway connected bin_`method'_score bin_akm_effect if bin_tag, sort ///
        msymbol(O) msize(medsmall) mcolor(navy) lcolor(navy) lwidth(medthin) ///
        xtitle("Mean AKM firm wage effect (log points)") ///
        ytitle("Mean `name' score") ///
        ylabel(,angle(horizontal) format(%5.2f)) xlabel(,format(%5.2f)) ///
        legend(off) graphregion(color(white)) plotregion(color(white)) ///
        xsize(7) ysize(3.35) name(binned_score_`method',replace)
    graph export `"`out'/figures/akm_`method'_score_binned.pdf"', replace
    latexlog `report': writeln "\begin{figure}[H]\centering\includegraphics[width=.96\textwidth]{figures/akm_`method'_score_binned.pdf}\caption{Binned AKM wage effects and `name' scores}\end{figure}"
}

latexlog `report': writeln "\clearpage"
latexlog `report': section "Computational diagnostics"
preserve
use `medians', clear
latexlog `report': writeln "\begin{table}[H]\centering\small\caption{Median internal phase timings (seconds)}\begin{tabular}{lrrrrr}\toprule Method & Threads & Input / graph & Solve & Store & Internal total\\\\\midrule"
forvalues row=1/`=_N' {
    local method_name = cond(method[`row']=="akm","AKM (fereg)",cond(method[`row']=="sorkin","Sorkin","Bradley--Terry"))
    foreach field in input_seconds solve_seconds store_seconds native_seconds {
        if missing(`field'[`row']) local `field'_fmt "---"
        else local `field'_fmt : display %8.3f `field'[`row']
    }
    local nt = threads[`row']
    latexlog `report': writeln "`method_name' & `nt' & `input_seconds_fmt' & `solve_seconds_fmt' & `store_seconds_fmt' & `native_seconds_fmt' \\\\"
}
latexlog `report': writeln "\bottomrule\end{tabular}\end{table}"
latexlog `report': writeln "Internal instrumentation has different boundaries. For fereg, input is native input loading, solve is the native estimation stage, and total ends before Stata publication. For ferank, input/graph includes panel ingestion, canonicalization and component discovery; solve includes ranking; store is plugin result storage. The wall-clock table is the primary timing comparison.\par"
restore
preserve
use `"`out'/timings.dta"', clear
keep if repetition==0
sort threads method
latexlog `report': writeln "\begin{table}[H]\centering\small\caption{Flow-graph size and numerical certificates}\begin{tabular}{lrrrrr}\toprule Method & Threads & SCC firms & All edges & Iterations & Certificate maximum\\\\\midrule"
forvalues row=1/`=_N' {
    if method[`row']!="akm" {
        local method_name = cond(method[`row']=="sorkin","Sorkin","Bradley--Terry")
        local nt = threads[`row']
        local nf : display %12.0fc N_results[`row']
        local ne : display %12.0fc N_edges[`row']
        local it : display %10.0f iterations[`row']
        local certificate = cond(method[`row']=="sorkin",residual_max[`row'],gradient_max[`row'])
        local certificate_fmt : display %9.2e `certificate'
        latexlog `report': writeln "`method_name' & `nt' & `nf' & `ne' & `it' & `certificate_fmt' \\\\"
    }
}
latexlog `report': writeln "\bottomrule\end{tabular}\end{table}"
latexlog `report': writeln "Firm counts refer to the selected SCC; edge counts cover the full canonical graph before component selection. Both methods use tolerance \(10^{-10}\), their default iteration budgets, and no smoothing or component bridging. The certificate maximum is the stationary-equation residual for Sorkin and the likelihood gradient for Bradley--Terry; these quantities have different scales. Full L1, Newton and thread diagnostics are retained in the CSV and Stata log. Every repeated score vector was checked against the first vector after centering, at \(10^{-8}\max(1,|s|)\), including across thread counts.\par"
restore
latexlog `report': section "Sample and model"
latexlog `report': writeln "The estimation sample has `matches_fmt' worker-firm matches, including movers and eligible stayers, drawn from the private FEVC 1996--2001 VWH panel. The prior preparation retained a leave-worker-out connected sample with at least two observations per worker. Year effects and a normalized cubic age profile were jointly fitted with worker and firm effects in the original preparation; this nuisance adjustment remains fixed on the restricted sample. This benchmark estimates \(y^{adj}_{it}=\alpha_i+\psi_{j(i,t)}+\varepsilon_{it}\) with fereg and saves \(\psi_j\). The source preparation has 18 fewer rows than the published KSS appendix. The restricted-profile firm-size rule follows \href{https://doi.org/10.1093/qje/qjy001}{Sorkin (2018)}, pp. 1341--1342; person-year weighting follows his Table II notes (p. 1344). Direct EE overlap, hires from nonemployment and bootstrap-coverage restrictions cannot be implemented from this annual adjusted panel. Quarterly transition data and structural size/offer/layoff adjustments are outside this benchmark.\par"
latexlog `report': writeln "Timed flow construction starts from the selected `obs_fmt' rows. A unit move is recorded between consecutive observed worker-years only when firms differ and the gap is at most one year. There are `moves_fmt' eligible moves and `gaps_fmt' gap breaks. Both methods select the largest directed strongly connected component. The restricted profile first selects the component after the size filter, then fits all three estimators on its firms. An excluded annual observation cannot be bridged because maxgap is one. A saved selection-score vector verifies that the induced graph gives the same Sorkin scores. Terminal observations remain in AKM and weighting. Raw move counts remain unit counts; person-year weights apply to descriptive comparisons, not to the flow estimators.\par"
latexlog `report': writeln "\clearpage"
latexlog `report': section "Reproducibility and timing boundaries"
latexlog `report': writeln "The private input is hash-pinned to SHA-256.\par{\small\texttt{\detokenize{e4a1928d98c1dbe7185634e14470b9361b58f8d5b33cceacc8d168ccdad4634e}}}\par Worker-year and observation IDs are unique; sample counts, finite values and year coverage are checked before estimation. The input remains outside the repository. Individual effects and raw timings are in the ignored, owner-only run directory.\par"
latexlog `report': writeln "Host: `cpu_model', `memory_gib' GiB RAM (`machine'); OS: `os'; Stata/MP `stata_version'; `machine_processors' detected cores; `stata_processors' Stata processors. Native settings: `native_threads'. The launcher records the CPU model, memory, source revisions, dirty-source status, every staged ado/plugin hash, input hash, host load and whole-process elapsed time in \texttt{run\_manifest.json} and \texttt{execution.json}. Snapshots prevent concurrent package edits from changing the benchmark mid-run. Built plugin hashes are authoritative binary identities; a repository revision alone does not establish which dirty-source bytes produced an existing binary.\par"
latexlog `report': writeln "This is a local repeated-run benchmark on a workstation, with normal operating-system background activity, not an isolated-node throughput qualification. Three repeats give a useful range but do not remove thermal, cache or scheduling effects. The programs are distinct estimators and their runtimes are not interchangeable speedup claims. All commands run sequentially. In the restricted profile, sample preparation loads ferank before all timed calls. Initial timings therefore mean the first measured command at each setting, not a fresh-process cold start. External panel import occurs once and data remain in memory during repetitions.\par"
latexlog `report': writeln "\begin{verbatim}"
latexlog `report': writeln "fereg y_adjusted, absorb(worker akm_firm=firm)"
latexlog `report': writeln "    residuals(akm_residual) keepsingletons"
latexlog `report': writeln "    threads(T) tolerance(1e-10)"
latexlog `report': writeln ""
latexlog `report': writeln "ferank firm, worker(worker) time(year)"
latexlog `report': writeln "    method(sorkin|bradleyterry) maxgap(1)"
latexlog `report': writeln "    component(largest) normalize(mean)"
latexlog `report': writeln "    threads(T) tolerance(1e-10) frame(ranking)"
latexlog `report': writeln "\end{verbatim}"
latexlog `report': writeln "Entry point: \texttt{bench/veneto\_full.do}; report-only companion: \texttt{bench/veneto\_report.do}. Running the entry point with mode \texttt{report} regenerates the report from saved benchmark outputs without refitting the models. Tables are written through latexlog; all eight figures are generated in Stata and saved individually. The 20 bin means and firm counts are retained in \texttt{binned\_scatter\_data.csv}.\par"
latexlog `report': close
timer off 93
quietly timer list 93
display as result "VENETO_REPORT_GENERATION_SECONDS=" r(t93)
timer clear 94
timer on 94
latexlog `report': pdf
/* Check a fresh, strict second pass; legacy latexlog pdf does not return TeX status. */
capture erase `"`out'/veneto_benchmark.pdf"'
local prior_directory `"`c(pwd)'"'
cd `"`out'"'
forvalues pass=1/2 {
    shell /Library/TeX/texbin/pdflatex -halt-on-error -no-shell-escape -interaction=nonstopmode veneto_benchmark.tex > pdf_compile.log 2>&1
}
cd `"`prior_directory'"'
tempname compilation
file open `compilation' using `"`out'/pdf_compile.log"', read text
local compiled 0
file read `compilation' buildline
while r(eof)==0 {
    if strpos(`"`buildline'"',"Output written on veneto_benchmark.pdf") local compiled 1
    file read `compilation' buildline
}
file close `compilation'
assert `compiled'==1
timer off 94
quietly timer list 94
display as result "VENETO_PDF_COMPILATION_SECONDS=" r(t94)
confirm file `"`out'/veneto_benchmark.pdf"'
