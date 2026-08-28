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
    threads(8) frame(veneto_sorkin) replace
post `diagnostics' ("sorkin") (e(N_input)) (e(N_firms)) (e(N_results)) ///
    (e(N_edges)) (e(N_components)) (e(valid_moves)) (e(gap_breaks)) ///
    (e(same_firm_continuations)) (e(iterations)) (e(residual_max)) ///
    (e(residual_l1)) (.) (.) (.) (.) (e(threads)) ///
    (e(time_input_graph)) (e(time_solve_rank)) (e(time_total))
frame veneto_sorkin: export delimited using `"`output_dir'/sorkin.csv"', replace

ferank firm, worker(worker) time(year) method(bradleyterry) maxgap(2) ///
    component(largest) normalize(mean) tolerance(1e-10) maxiter(20000) ///
    threads(8) frame(veneto_bt) replace
post `diagnostics' ("bradleyterry") (e(N_input)) (e(N_firms)) (e(N_results)) ///
    (e(N_edges)) (e(N_components)) (e(valid_moves)) (e(gap_breaks)) ///
    (e(same_firm_continuations)) (e(iterations)) (.) (.) ///
    (e(ll)) (e(gradient_max)) (e(newton_residual)) ///
    (e(line_search_steps)) (e(threads)) (e(time_input_graph)) ///
    (e(time_solve_rank)) (e(time_total))
frame veneto_bt: export delimited using `"`output_dir'/bradleyterry.csv"', replace

postclose `diagnostics'
use `"`output_dir'/diagnostics.dta"', clear
export delimited using `"`output_dir'/diagnostics.csv"', replace
erase `"`output_dir'/diagnostics.dta"'
display as result "FERANK VENETO REPORT PASS"
log close
