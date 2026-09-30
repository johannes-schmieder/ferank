/*
Full private Veneto (1996--2001): AKM and firm-flow ranking benchmark.
Run from the ferank root, preferably through scripts/run_veneto_benchmark.py.
Arguments: input.csv output_dir fereg_root ferank_root repetitions "threads" mode sample_profile
mode=report regenerates figures/TeX/PDF from saved benchmark outputs.
All outputs are private, ignored working artifacts; never upload this run to CI.
*/
version 19.0
clear all
set more off
set varabbrev off
set linesize 200
set seed 20260929
set scheme s2color
args input out fereg_root ferank_root repetitions thread_list mode sample_profile
if `"`ferank_root'"' == "" local ferank_root `"`c(pwd)'"'
if `"`fereg_root'"' == "" local fereg_root `"`ferank_root'/../fereg"'
if `"`out'"' == "" local out `"`ferank_root'/report/output/veneto-full"'
if `"`repetitions'"' == "" local repetitions 3
if `"`thread_list'"' == "" local thread_list "1 8"
if `"`mode'"' == "" local mode "full"
if `"`sample_profile'"' == "" local sample_profile "sorkin"
local first_threads : word 1 of `thread_list'
assert `repetitions' >= 3
assert inlist(`"`mode'"', "full", "report")
assert inlist(`"`sample_profile'"', "full", "sorkin")
local licensed_processors = min(c(processors_lic), c(processors_mach), 8)
set processors `licensed_processors'
capture mkdir `"`ferank_root'/report/output"'
capture mkdir `"`out'"'
capture mkdir `"`out'/figures"'
adopath ++ `"`fereg_root'/stata"'
adopath ++ `"`fereg_root'/dist"'
adopath ++ `"`ferank_root'/stata"'
adopath ++ `"`ferank_root'/dist"'
local latexlog_dir : environment LATEXLOG_DIR
if `"`latexlog_dir'"' != "" adopath ++ `"`latexlog_dir'"'
log using `"`out'/stata_`mode'.log"', text replace name(veneto)
timer clear
timer on 99
capture noisily {
    which fereg
    which ferank
    which latexlog
    if `"`mode'"' == "full" {
        confirm file `"`input'"'
        /* Pin the FEVC prepared input, not the public teaching extract. */
        shell /usr/bin/shasum -a 256 "`input'" > "`out'/input.sha256"
        tempname hashfile
        file open `hashfile' using `"`out'/input.sha256"', read text
        file read `hashfile' hashline
        file close `hashfile'
        local actual_hash : word 1 of `hashline'
        assert `"`actual_hash'"' == "e4a1928d98c1dbe7185634e14470b9361b58f8d5b33cceacc8d168ccdad4634e"
        timer on 90
        import delimited `"`input'"', clear varnames(1) asdouble
        timer off 90
        quietly timer list 90
        scalar import_seconds = r(t90)
        timer on 92
        assert _N == 5163428
        assert inrange(year,1996,2001)
        assert !missing(year,worker,firm,observation_key,y_adjusted)
        isid worker year
        isid observation_key
        egen byte worker_tag = tag(worker)
        quietly count if worker_tag
        assert r(N) == 1106419
        drop worker_tag
        egen byte firm_tag = tag(firm)
        quietly count if firm_tag
        assert r(N) == 86647
        drop firm_tag
        egen byte match_tag = tag(worker firm)
        quietly count if match_tag
        assert r(N) == 1700466
        drop match_tag
        timer off 92
        quietly timer list 92
        scalar validation_seconds = r(t92)
        scalar source_rows = _N
        scalar source_workers = 1106419
        scalar source_firms = 86647
        scalar source_matches = 1700466
        timer on 95
        /* Sorkin singleton years are terminal observations, not one-row workers.
           Determine eligibility in the original panel, before any firm filtering. */
        sort worker year
        by worker: gen byte observed_again = _n<_N
        egen long nonsingleton_years = total(observed_again), by(firm)
        bysort firm: gen long source_person_years = _N
        quietly count if observed_again
        scalar source_nonsingleton = r(N)
        assert source_nonsingleton==4057009
        preserve
        bysort firm: keep if _n==1
        keep firm source_person_years nonsingleton_years
        gen byte size_eligible = nonsingleton_years>=90
        quietly save `"`out'/sample_firm_counts.dta"', replace
        restore
        scalar size_eligible_firms = source_firms
        scalar size_eligible_rows = source_rows
        scalar minimum_nonsingleton = 0
        scalar selection_loads_ferank = 0
        if `"`sample_profile'"' == "sorkin" {
            scalar minimum_nonsingleton = 90
            keep if nonsingleton_years>=minimum_nonsingleton
            egen byte size_tag = tag(firm)
            quietly count if size_tag
            scalar size_eligible_firms = r(N)
            scalar size_eligible_rows = _N
            drop size_tag
            assert size_eligible_firms==7942 & size_eligible_rows==3100256
            /* Untimed selection call prepares a common identified sample.
               maxgap(1) prevents bridging an excluded annual observation. */
            ferank firm, worker(worker) time(year) method(sorkin) maxgap(1) ///
                component(largest) normalize(mean) tolerance(1e-10) ///
                threads(`first_threads') frame(sample_component) replace
            assert e(N_results)==7238
            scalar selection_loads_ferank = 1
            tempfile selected_firms
            frame sample_component: rename firm_id firm
            frame sample_component: keep firm score
            frame sample_component: save `"`out'/sample_scc_reference.dta"', replace
            frame sample_component: keep firm
            frame sample_component: save `selected_firms', replace
            merge m:1 firm using `selected_firms', keep(match) nogen
            frame drop sample_component
            assert _N==2973781
            assert nonsingleton_years>=90
        }
        quietly summarize nonsingleton_years, meanonly
        scalar sample_min_nonsingleton = r(min)
        drop observed_again nonsingleton_years source_person_years
        timer off 95
        quietly timer list 95
        scalar sample_preparation_seconds = r(t95)
        timer on 96
        sort worker year
        quietly by worker: gen byte transition = _n>1
        quietly by worker: gen byte gap = transition & year-year[_n-1]>1
        quietly by worker: gen byte move = transition & !gap & firm!=firm[_n-1]
        quietly count if move
        scalar adjacent_moves = r(N)
        quietly count if gap
        scalar panel_gap_breaks = r(N)
        drop transition gap move
        quietly compress year worker firm observation_key
        scalar panel_rows = _N
        egen byte worker_tag = tag(worker)
        quietly count if worker_tag
        scalar panel_workers = r(N)
        drop worker_tag
        egen byte firm_tag = tag(firm)
        quietly count if firm_tag
        scalar panel_firms = r(N)
        drop firm_tag
        egen byte match_tag = tag(worker firm)
        quietly count if match_tag
        scalar panel_matches = r(N)
        drop match_tag
        if `"`sample_profile'"' == "sorkin" {
            assert panel_workers==715293 & panel_firms==7238 & panel_matches==869927
            assert adjacent_moves==132899
        }
        timer off 96
        quietly timer list 96
        scalar sample_preparation_seconds = sample_preparation_seconds+r(t96)
        display as result "VENETO_SAMPLE profile=`sample_profile' rows=" panel_rows " firms=" panel_firms " workers=" panel_workers
        tempfile panel baseline current
        quietly save `panel'
        tempname calls
        postfile `calls' str16 method int threads repetition order rc ///
            double wall_seconds input_seconds solve_seconds store_seconds native_seconds ///
            N_input N_results N_edges iterations residual_max residual_l1 gradient_max ///
            newton_residual valid_moves gap_breaks using `"`out'/timings.dta"', replace every(1)
        local methods "akm sorkin bradleyterry"
        foreach nt of local thread_list {
            assert inrange(`nt',1,16)
            forvalues rep=0/`repetitions' {
                forvalues position=1/3 {
                    local index = mod(`position'-1+`rep',3)+1
                    local method : word `index' of `methods'
                    capture drop akm_firm akm_residual
                    capture frame drop ranking
                    ereturn clear
                    timer clear 91
                    display as text "VENETO_CALL_START method=`method' threads=`nt' rep=`rep' order=`position' `c(current_time)'"
                    timer on 91
                    if `"`method'"' == "akm" {
                        capture noisily fereg y_adjusted, absorb(worker akm_firm=firm) ///
                            residuals(akm_residual) keepsingletons threads(`nt') tolerance(1e-10)
                    }
                    else {
                        capture noisily ferank firm, worker(worker) time(year) ///
                            method(`method') maxgap(1) component(largest) normalize(mean) ///
                            tolerance(1e-10) threads(`nt') frame(ranking) replace
                    }
                    local call_rc = _rc
                    timer off 91
                    quietly timer list 91
                    local wall_seconds = r(t91)
                    foreach metric in input_seconds solve_seconds store_seconds native_seconds ///
                        N_input N_results N_edges iterations residual_max residual_l1 ///
                        gradient_max newton_residual valid_moves gap_breaks {
                        local `metric' = .
                    }
                    if !`call_rc' {
                        if `"`method'"' == "akm" {
                            local N_input = e(N)
                            local N_results = scalar(panel_firms)
                            local input_seconds = el(e(fereg_runtime),19,2)
                            local solve_seconds = el(e(fereg_runtime),20,2)
                            local native_seconds = el(e(fereg_runtime),21,2)
                        }
                        else {
                            local input_seconds = e(time_input_graph)
                            local solve_seconds = e(time_solve_rank)
                            local store_seconds = e(time_store)
                            local native_seconds = e(time_total)
                            foreach metric in N_input N_results N_edges iterations residual_max ///
                                residual_l1 gradient_max newton_residual valid_moves gap_breaks {
                                local `metric' = e(`metric')
                            }
                        }
                    }
                    post `calls' ("`method'") (`nt') (`rep') (`position') (`call_rc') ///
                        (`wall_seconds') (`input_seconds') (`solve_seconds') (`store_seconds') ///
                        (`native_seconds') (`N_input') (`N_results') (`N_edges') (`iterations') ///
                        (`residual_max') (`residual_l1') (`gradient_max') (`newton_residual') ///
                        (`valid_moves') (`gap_breaks')
                    display as result "VENETO_CALL_DONE method=`method' threads=`nt' rep=`rep' rc=`call_rc' seconds=`wall_seconds'"
                    if `call_rc' {
                        postclose `calls'
                        error `call_rc'
                    }
                    /* Save and validate outputs outside the command timer. */
                    if `"`method'"' == "akm" {
                        assert e(N) == panel_rows
                        assert e(sample)
                        assert !missing(akm_firm,akm_residual)
                        ereturn list
                        matrix list e(fereg_solver)
                        matrix list e(fereg_certificate)
                        preserve
                        keep firm akm_firm akm_residual
                        quietly bysort firm: assert abs(akm_firm-akm_firm[1])<1e-10
                        quietly egen double firm_moment = mean(akm_residual), by(firm)
                        quietly summarize firm_moment, meanonly
                        assert max(abs(r(min)),abs(r(max)))<1e-7
                        collapse (first) akm_firm (count) employment=akm_residual, by(firm)
                        rename akm_firm score
                        quietly save `current', replace
                    }
                    else {
                        assert e(N_input) == panel_rows
                        assert e(valid_moves) == adjacent_moves
                        assert e(gap_breaks) == panel_gap_breaks
                        assert `"`e(convergence_certificate)'"' != ""
                        ereturn list
                        preserve
                        frame ranking: assert !missing(firm_id,score,rank,percentile)
                        frame ranking: isid firm_id
                        frame ranking: save `current', replace
                        use `current', clear
                        rename firm_id firm
                        quietly save `current', replace
                    }
                    if `rep'==0 & `nt'==`first_threads' {
                        if `"`sample_profile'"'=="sorkin" & `"`method'"'=="sorkin" {
                            rename score selected_score
                            merge 1:1 firm using `"`out'/sample_scc_reference.dta"', keepusing(score) assert(match) nogen
                            quietly summarize selected_score, meanonly
                            local selected_mean = r(mean)
                            quietly summarize score, meanonly
                            local reference_mean = r(mean)
                            assert abs((selected_score-`selected_mean')-(score-`reference_mean'))<=1e-8*max(1,abs(score-`reference_mean'))
                            drop score
                            rename selected_score score
                            assert e(N_edges)==75541
                        }
                        quietly save `"`out'/`method'_baseline.dta"', replace
                    }
                    else {
                        rename score current_score
                        merge 1:1 firm using `"`out'/`method'_baseline.dta"', ///
                            keepusing(score) assert(match) nogen
                        quietly summarize current_score, meanonly
                        local current_mean = r(mean)
                        quietly summarize score, meanonly
                        local baseline_mean = r(mean)
                        gen double score_difference = (current_score-`current_mean')-(score-`baseline_mean')
                        assert abs(score_difference) <= 1e-8*max(1,abs(score-`baseline_mean'))
                        quietly summarize score_difference, meanonly
                        display as text "VENETO_REPEAT_CHECK method=`method' threads=`nt' rep=`rep' maxdiff=" max(abs(r(min)),abs(r(max)))
                    }
                    restore
                }
            }
        }
        postclose `calls'
        preserve
        use `"`out'/timings.dta"', clear
        assert rc==0
        export delimited using `"`out'/timings.csv"', replace
        restore
        /* Compact, aggregate run metadata permits report-only regeneration. */
        preserve
        clear
        set obs 1
        foreach name in import_seconds validation_seconds panel_rows panel_workers panel_firms ///
            panel_matches adjacent_moves panel_gap_breaks source_rows source_workers source_firms ///
            source_matches source_nonsingleton size_eligible_firms size_eligible_rows ///
            minimum_nonsingleton sample_min_nonsingleton sample_preparation_seconds selection_loads_ferank {
            gen double `name' = scalar(`name')
        }
        gen str12 sample_profile = "`sample_profile'"
        gen str20 comparison_weighting = "person_years"
        gen str20 run_date = "`c(current_date)'"
        gen str20 run_time = "`c(current_time)'"
        gen str40 machine = "`c(machine_type)'"
        gen str20 os = "`c(os)'"
        gen double stata_version = c(stata_version)
        gen double stata_processors = c(processors)
        gen double machine_processors = c(processors_mach)
        gen str40 native_threads = "`thread_list'"
        gen int measured_repetitions = `repetitions'
        quietly save `"`out'/run_metadata.dta"', replace
        export delimited using `"`out'/run_metadata.csv"', replace
        restore
        display as result "FERANK FULL VENETO ESTIMATION PASS"
    }
    do `"`ferank_root'/bench/veneto_report.do"' `"`out'"'
    timer off 99
    quietly timer list 99
    display as result "FERANK FULL VENETO REPORT PASS total_do_seconds=" r(t99)
}
local rc = _rc
tempname statusfile
file open `statusfile' using `"`out'/stata_`mode'.status"', write text replace
file write `statusfile' "`rc'" _n
file close `statusfile'
log close veneto
exit `rc'
