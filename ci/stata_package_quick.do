version 18.0
set more off
set varabbrev off
assert c(stata_version) >= 18
adopath ++ "stata"
ferank, selftest

* The caller's unrelated frame must survive every success and failure.
tempname sentinel_frame
frame create `sentinel_frame'
frame `sentinel_frame': set obs 1
frame `sentinel_frame': generate byte sentinel = 42
quietly frames dir
local original_frames `"`r(frames)'"'

clear
input double(origin destination flow)
1 2 4
2 1 1
2 3 3
3 2 1
3 1 2
1 3 1
end
generate long row = _n
label variable origin "Original origin label"
clonevar original_origin = origin
clonevar original_destination = destination
clonevar original_flow = flow
ferank origin destination, method(sorkin) flow(flow) ///
    generate(sr_origin sr_destination) score(ss_origin ss_destination) ///
    percentile(sp_origin sp_destination) componentid(sc_origin sc_destination)
assert row == _n
assert origin == original_origin
assert destination == original_destination
assert flow == original_flow
local original_label : variable label origin
assert `"`original_label'"' == "Original origin label"
assert e(N_results) == 3
assert e(N_mapped) == _N
assert e(N_mapped_origin) == _N & e(N_mapped_destination) == _N
assert e(N_components_estimated) == 1
assert e(residual_max) <= 1e-10
assert `"`e(convergence_certificate)'"' == "success"
assert `"`e(rankvars)'"' == "sr_origin sr_destination"
assert `"`e(result_frame)'"' == ""
assert strpos(`"`e(cmdline)'"', "_work") == 0
assert e(threads) == 1
assert e(time_total) >= e(time_input_graph) + e(time_solve_rank)
assert !missing(sr_origin, sr_destination, ss_origin, ss_destination)
assert sp_origin == 100*(3-sr_origin)/2
assert sc_origin == sc_destination
quietly summarize ss_origin, meanonly
assert abs(r(mean)) < 1e-10
estat convergence
estat components

* Every endpoint is joined by ID, rather than result-row order.
forvalues firm = 1/3 {
    quietly summarize ss_origin if origin == `firm', meanonly
    local value = r(mean)
    assert abs(ss_destination-`value') < 1e-12 if destination == `firm'
}
ferank origin destination, method(sorkin) flow(flow) engine(reference) ///
    score(ref_origin ref_destination)
assert abs(ref_origin-ss_origin) < 1e-8
assert abs(ref_destination-ss_destination) < 1e-8
ferank origin destination, method(sorkin) flow(flow) ///
    normalize(reference) reference(1) score(zero_origin zero_destination)
assert abs(zero_origin) < 1e-12 if origin == 1
assert abs(zero_destination) < 1e-12 if destination == 1
generate double normweight = cond(origin == 1, 2, 1)
ferank origin destination, method(sorkin) flow(flow) ///
    normalize(weighted) normweight(normweight) score(w_origin w_destination)
quietly summarize w_origin [aw=normweight], meanonly
assert abs(r(mean)) < 1e-10

ferank origin destination, method(bradleyterry) flow(flow) ///
    generate(br_origin br_destination) score(bs_origin bs_destination) verbose
assert e(gradient_max) <= 1e-10
assert `"`e(linear_route)'"' != ""
assert row == _n

* Invalid contracts and name collisions must not create partial outputs.
foreach command in ///
    "generate(only_one)" ///
    "generate(dup dup)" ///
    "generate(new_origin new_destination) score(new_origin other)" ///
    "generate(new_origin new_destination) score(origin other)" ///
    "frame(old_frame)" ///
    "generate(new_origin new_destination) replace" {
    capture noisily ferank origin destination, method(sorkin) flow(flow) `command'
    assert _rc != 0
    capture confirm variable new_origin
    assert _rc == 111
    assert row == _n
    assert origin == original_origin
}
capture noisily ferank origin destination, method(sorkin) flow(flow)
assert _rc == 198

* Analytic two-firm Bradley-Terry: log score difference = log(win ratio).
clear
input str2 origin str2 destination double flow
"aa" "bb" 4
"bb" "aa" 1
end
ferank origin destination, method(bradleyterry) flow(flow) ///
    generate(rank_o rank_d) score(score_o score_d) percentile(pct_o pct_d)
assert abs(score_d[1]-score_o[1]-ln(4)) < 1e-8
assert rank_o[1] == 2 & rank_d[1] == 1
assert pct_o[1] == 0 & pct_d[1] == 100
assert score_o[1] == score_d[2]
assert score_o[2] == score_d[1]

* Exact ties need fractional ranks and the midpoint percentile.
replace flow = 1
drop rank_o rank_d score_o score_d pct_o pct_d
ferank origin destination, method(sorkin) flow(flow) ///
    generate(rank_o rank_d) percentile(pct_o pct_d)
assert rank_o == 1.5 & rank_d == 1.5
assert pct_o == 50 & pct_d == 50

* Only selected rows receive values, even when excluded rows use ranked firms.
clear
input double(origin destination flow use_row)
1 2 4 1
2 1 1 1
1 2 999 0
2 1 999 0
end
ferank origin destination if use_row in 1/3, method(bradleyterry) flow(flow) ///
    score(score_o score_d) generate(rank_o rank_d)
assert e(N_input) == 2 & e(N_mapped) == 2
assert abs(score_d[1]-score_o[1]-ln(4)) < 1e-8
assert missing(score_o, score_d, rank_o, rank_d) if !use_row

* Panels: unsorted rows, strings, gaps, missing IDs and nonmoving workers.
clear
input str1 worker double time str2 firm
"c" 2 "aa"
"a" 1 "aa"
"b" 2 "aa"
"a" 2 "bb"
"b" 1 "bb"
"a" 3 ""
"a" 4 "aa"
"c" 1 "aa"
"d" 1 "zz"
"d" 2 "zz"
"e" 1 "aa"
"e" 3 "bb"
end
generate long row = _n
ferank firm, worker(worker) time(time) method(sorkin) ///
    generate(rank) score(score) percentile(pct) componentid(group)
assert row == _n
assert e(valid_moves) == 2
assert e(gap_breaks) == 1
assert e(missing_firm_breaks) == 1
assert e(N_results) == 2
assert e(N_mapped) == 9
assert rank == 1.5 if inlist(firm, "aa", "bb")
assert missing(rank, score, pct, group) if inlist(firm, "", "zz")
assert !missing(rank) if worker == "c"
capture noisily ferank firm, worker(worker) time(time) method(sorkin) ///
    generate(bad1 bad2)
assert _rc == 198

* if/in affect panel move construction and generated-value placement.
clear
input double(worker time firm)
1 1 10
1 2 20
2 1 20
2 2 10
3 1 10
3 2 20
end
ferank firm if worker <= 2 in 1/5, worker(worker) time(time) ///
    method(sorkin) generate(rank) score(score)
assert e(N_input) == 4 & e(valid_moves) == 2
assert rank == 1.5 if worker <= 2
assert missing(rank, score) if worker == 3

* Separate components: ranks are local, and edge endpoints may differ.
clear
input double(origin destination flow)
1 2 1
2 1 1
10 11 1
11 10 1
2 10 1
end
ferank origin destination, method(sorkin) flow(flow) component(all) ///
    generate(rank_o rank_d) componentid(group_o group_d)
assert e(N_components_estimated) == 2
assert e(N_results) == 4
assert rank_o == 1.5 & rank_d == 1.5
assert group_o != group_d in 5
assert group_o == group_d in 1/4
ferank origin destination, method(sorkin) flow(flow) component(largest) ///
    generate(largest_o largest_d)
assert e(N_results) == 2
assert !missing(largest_o, largest_d) in 1/2
assert missing(largest_o, largest_d) in 3/4
assert !missing(largest_o) & missing(largest_d) in 5
assert e(N_mapped_origin) == 3 & e(N_mapped_destination) == 2
assert e(N_mapped) == 2 & e(N_unmapped) == 3

* A filtered row still receives its firms' values if both firms are ranked.
clear
input double(origin destination flow)
1 2 4
2 1 1
1 1 99
1 2 0
9 9 99
end
ferank origin destination, method(sorkin) flow(flow) generate(rank_o rank_d)
assert !missing(rank_o, rank_d) in 1/4
assert missing(rank_o, rank_d) in 5
assert e(N_results) == 2

* Failed solve/invalid data: existing variables, order and frames survive.
replace flow = -1 in 2
generate long row = _n
clonevar original_origin = origin
capture noisily ferank origin destination, method(sorkin) flow(flow) ///
    generate(failure_o failure_d) score(failure_s failure_t)
assert _rc == 459
assert row == _n & origin == original_origin
foreach variable in failure_o failure_d failure_s failure_t {
    capture confirm variable `variable'
    assert _rc == 111
}
replace flow = 1 in 2
capture noisily ferank origin destination, method(sorkin) flow(flow) ///
    lazy(1) maxiter(1) score(failure_s failure_t)
assert _rc == 430
capture confirm variable failure_s
assert _rc == 111
frame `sentinel_frame': assert sentinel == 42
quietly frames dir
assert `"`r(frames)'"' == `"`original_frames'"'
capture frame ferank_results: count
assert _rc == 111
frame drop `sentinel_frame'

* Quiet calls must not leak progress or summary output.
tempfile quiet_log
log using `quiet_log', text name(quiet_test) replace
quietly ferank origin destination, method(sorkin) flow(flow) ///
    score(quiet_o quiet_d)
log close quiet_test
tempname handle
file open `handle' using `quiet_log', read text
file read `handle' line
while r(eof)==0 {
    assert strpos(`"`line'"', "Firm rankings from worker flows") == 0
    file read `handle' line
}
file close `handle'

do ci/stata_help_examples.do
display as result "FERANK GENERATED VARIABLES AND TRANSACTIONS PASS"
display as result "FERANK STATA PACKAGE QUICK PASS"
