version 18.0
set more off
set varabbrev off
adopath ++ "stata"

* Execute the exact help blocks through the clickable-example helper.
* Sentinel data and an unrelated pre-existing frame must survive.
clear
set obs 3
generate long sentinel_id = 4-_n
generate str12 sentinel_text = "caller data"
label variable sentinel_id "Original caller order"
tempname sentinel_frame
frame create `sentinel_frame'
frame `sentinel_frame': set obs 1
frame `sentinel_frame': generate long sentinel_value = 123

foreach example in edges panel compare components normalization {
    ferank_run `example' using ferank.sthlp
    assert _N == 3
    assert sentinel_id == 4-_n
    assert sentinel_text == "caller data"
    local original_label : variable label sentinel_id
    assert `"`original_label'"' == "Original caller order"
    frame `sentinel_frame': assert sentinel_value == 123
    assert `"`e(cmd)'"' == "ferank"
    assert `"`e(convergence_certificate)'"' == "success"
    if "`example'"=="panel" {
        assert e(N_results)==2
        assert e(valid_moves)==2
        assert e(gap_breaks)==1
        assert e(missing_firm_breaks)==1
    }
    if "`example'"=="components" {
        assert e(N_results)==4
        assert e(N_components)==2
    }
    assert `"`e(result_frame)'"' == ""
}

* Lookup and executed-code failures must restore caller data as well.
capture noisily ferank_run nonexistent using ferank.sthlp
assert _rc==111
assert _N==3
assert sentinel_id==4-_n

tempfile bad_help
tempname help_handle
file open `help_handle' using `"`bad_help'"', write text replace
file write `help_handle' "{* example_start - failure}{...}" _n
file write `help_handle' "clear" _n
file write `help_handle' "error 459" _n
file write `help_handle' "{* example_end}{...}" _n
file close `help_handle'
capture noisily ferank_run failure using `"`bad_help'"'
assert _rc==459
assert _N==3
assert sentinel_id==4-_n
frame `sentinel_frame': assert sentinel_value==123
frame drop `sentinel_frame'

display as result "FERANK STATA HELP EXAMPLES PASS"
