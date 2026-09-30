version 19.0
clear all
set more off
set varabbrev off

args repo_root input_csv output_dir log_file
confirm file `"`input_csv'"'
capture mkdir `"`output_dir'"'
adopath ++ `"`repo_root'/stata"'
capture log close _all
log using `"`log_file'"', text replace

import delimited using `"`input_csv'"', varnames(nonames) clear
rename v1 worker
rename v2 firm
rename v3 year
rename v4 outcome
keep worker firm year outcome
isid worker year

tempname diagnostics
postfile `diagnostics' str16 method double N_input N_firms N_results N_edges ///
    N_components valid_moves gap_breaks same_firm iterations residual_max ///
    residual_l1 log_likelihood gradient_max newton_residual ///
    line_search_steps threads time_input_graph time_solve_rank time_total ///
    using `"`output_dir'/diagnostics.dta"', replace

ferank firm, worker(worker) time(year) method(sorkin) maxgap(2) ///
    component(largest) normalize(mean) tolerance(1e-10) maxiter(20000) ///
    threads(8) generate(sr_rank) score(sr_score) percentile(sr_pct) componentid(sr_component)
post `diagnostics' ("sorkin") (e(N_input)) (e(N_firms)) (e(N_results)) ///
    (e(N_edges)) (e(N_components)) (e(valid_moves)) (e(gap_breaks)) ///
    (e(same_firm_continuations)) (e(iterations)) (e(residual_max)) ///
    (e(residual_l1)) (.) (.) (.) (.) (e(threads)) ///
    (e(time_input_graph)) (e(time_solve_rank)) (e(time_total))
preserve
keep if !missing(sr_score)
bysort firm: keep if _n==1
keep firm sr_rank sr_score sr_pct sr_component
rename firm firm_id
rename sr_rank rank
rename sr_score score
rename sr_pct percentile
rename sr_component component_id
export delimited using `"`output_dir'/sorkin.csv"', replace
restore

ferank firm, worker(worker) time(year) method(bradleyterry) maxgap(2) ///
    component(largest) normalize(mean) tolerance(1e-10) maxiter(20000) ///
    threads(8) generate(bt_rank) score(bt_score) percentile(bt_pct) componentid(bt_component)
post `diagnostics' ("bradleyterry") (e(N_input)) (e(N_firms)) (e(N_results)) ///
    (e(N_edges)) (e(N_components)) (e(valid_moves)) (e(gap_breaks)) ///
    (e(same_firm_continuations)) (e(iterations)) (.) (.) ///
    (e(ll)) (e(gradient_max)) (e(newton_residual)) ///
    (e(line_search_steps)) (e(threads)) (e(time_input_graph)) ///
    (e(time_solve_rank)) (e(time_total))
preserve
keep if !missing(bt_score)
bysort firm: keep if _n==1
keep firm bt_rank bt_score bt_pct bt_component
rename firm firm_id
rename bt_rank rank
rename bt_score score
rename bt_pct percentile
rename bt_component component_id
export delimited using `"`output_dir'/bradleyterry.csv"', replace
restore

postclose `diagnostics'
use `"`output_dir'/diagnostics.dta"', clear
export delimited using `"`output_dir'/diagnostics.csv"', replace
erase `"`output_dir'/diagnostics.dta"'
display as result "FERANK VENETO REPORT PASS"
log close
