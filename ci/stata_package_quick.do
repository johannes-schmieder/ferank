version 18.0
set more off
set varabbrev off

do ci/stata_smoke.do
adopath ++ "stata"
ferank, selftest

capture frame drop sorkin_result
capture frame drop bt_result
capture frame drop panel_result
capture frame drop string_result
capture frame drop reference_result
capture frame drop reference_norm_result
capture frame drop weighted_result
capture frame drop all_components_result

clear
input double(origin destination flow)
1 2 4
2 1 1
2 3 3
3 2 1
3 1 2
1 3 1
end
clonevar original_origin = origin
clonevar original_destination = destination
clonevar original_flow = flow
ferank origin destination, method(sorkin) flow(flow) ///
    frame(sorkin_result) replace tolerance(1e-10)
assert origin == original_origin
assert destination == original_destination
assert flow == original_flow
assert e(N_results) == 3
assert e(residual_max) <= 1e-10
assert e(threads) == 1
assert e(time_input_graph) >= 0
assert e(time_solve_rank) >= 0
assert e(time_store) >= 0
assert e(time_total) >= e(time_input_graph) + e(time_solve_rank)
frame sorkin_result: assert _N == 3
frame sorkin_result: summarize score, meanonly
assert abs(r(mean)) < 1e-10
frame sorkin_result: assert !missing(revealed_value_q)
estat convergence
estat components

frame sorkin_result: summarize score if firm_id == 1, meanonly
local plugin_score_1 = r(mean)
ferank origin destination, method(sorkin) flow(flow) engine(reference) ///
    frame(reference_result) replace tolerance(1e-10)
frame reference_result: summarize score if firm_id == 1, meanonly
assert abs(r(mean) - `plugin_score_1') < 1e-8

ferank origin destination, method(sorkin) flow(flow) ///
    normalize(reference) reference(1) frame(reference_norm_result) replace
frame reference_norm_result: assert abs(score) < 1e-12 if firm_id == 1

generate double normweight = cond(origin == 1, 2, 1)
ferank origin destination, method(sorkin) flow(flow) ///
    normalize(weighted) normweight(normweight) frame(weighted_result) replace
frame weighted_result: generate double weighted_score = score * cond(firm_id == 1, 2, 1)
frame weighted_result: summarize weighted_score, meanonly
assert abs(r(sum)) < 1e-10

ferank origin destination, method(bradleyterry) flow(flow) ///
    frame(bt_result) replace tolerance(1e-10)
assert e(N_results) == 3
assert e(gradient_max) <= 1e-10
frame bt_result: assert _N == 3
frame bt_result: summarize score, meanonly
assert abs(r(mean)) < 1e-10
frame bt_result: assert missing(revealed_value_q)
estat convergence

clear
input double(worker time firm)
1 1 10
1 2 20
1 3 .
1 4 10
2 1 20
2 2 10
end
ferank firm, worker(worker) time(time) method(sorkin) ///
    frame(panel_result) replace
assert e(valid_moves) == 2
assert e(missing_firm_breaks) == 1
frame panel_result: assert _N == 2

clear
input str1 origin str1 destination double flow
"a" "b" 2
"b" "a" 1
end
ferank origin destination, method(bradleyterry) flow(flow) ///
    frame(string_result) replace
frame string_result: confirm string variable firm_id
frame string_result: assert inlist(firm_id, "a", "b")

clear
input double(origin destination flow)
1 2 1
2 1 1
10 11 1
11 10 1
end
ferank origin destination, method(sorkin) flow(flow) component(all) ///
    frame(all_components_result) replace
frame all_components_result: assert _N == 4
frame all_components_result: bysort component_id: assert _N == 2

clear
input double(origin destination flow)
1 2 1
2 1 -1
end
clonevar original_origin = origin
capture noisily ferank origin destination, method(sorkin) flow(flow) ///
    frame(should_not_exist)
assert _rc == 459
assert origin == original_origin
capture frame should_not_exist: count
assert _rc != 0

display as result "FERANK STATA PACKAGE QUICK PASS"
