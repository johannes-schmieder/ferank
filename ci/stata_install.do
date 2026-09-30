version 18.0
set more off
set varabbrev off
args source install_dir example_dir

sysdir set PLUS `"`install_dir'"'
net set ado `"`install_dir'"'

* The exact README installation block, with only its source URL substituted
* for the optional staged-local-package test.
do `"`example_dir'/installation.do"'
foreach command in ferank ferank_load ferank_estat ferank_run {
    findfile `command'.ado
    assert strpos(`"`r(fn)'"', `"`install_dir'"') == 1
}
findfile ferank.sthlp
assert strpos(`"`r(fn)'"', `"`install_dir'"') == 1
findfile ferank_macos.plugin
assert strpos(`"`r(fn)'"', `"`install_dir'"') == 1

* Reinstallation must succeed without relying on source-tree ado files.
net install ferank, replace from(`"`source'"')

clear
set obs 3
generate long sentinel = 4-_n
label variable sentinel "Caller data"
do `"`example_dir'/example1.do"'
assert _N == 3
assert sentinel == 4-_n
assert e(N_results) == 3
assert e(valid_moves) == 6
assert `"`e(method)'"' == "sorkin"
assert `"`e(convergence_certificate)'"' == "success"

do `"`example_dir'/example2.do"'
assert _N == 3
assert sentinel == 4-_n
assert e(N_results) == 3
assert `"`e(method)'"' == "bradleyterry"
assert `"`e(convergence_certificate)'"' == "success"

foreach example in edges panel compare components normalization {
    ferank_run `example' using ferank.sthlp
    assert _N == 3
    assert sentinel == 4-_n
    assert `"`e(convergence_certificate)'"' == "success"
}
local original_label : variable label sentinel
assert `"`original_label'"' == "Caller data"
display as result "FERANK ISOLATED INSTALL AND README EXAMPLES PASS"
