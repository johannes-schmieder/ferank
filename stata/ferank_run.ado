*! ferank_run 0.1.0 30sep2026
*! Run marked examples embedded in ferank.sthlp, restoring caller data.
*! Marker convention follows fevc_run and Robert Picard's geo2xy pattern.

program define ferank_run
    version 18.0
    syntax anything(name=example_name id="example name") using/

    preserve
    capture noisily _ferank_run_example `example_name' using `"`using'"'
    local example_rc = _rc
    capture restore
    if _rc {
        di as error "ferank_run could not restore the caller's data"
        exit 498
    }
    exit `example_rc'
end

program define _ferank_run_example
    version 18.0
    syntax anything(name=example_name id="example name") using/

    capture confirm file `"`using'"'
    if !_rc local help_file `"`using'"'
    else {
        capture findfile `"`using'"'
        if _rc {
            di as error `"help file `using' was not found on the Stata adopath"'
            exit 601
        }
        local help_file `"`r(fn)'"'
    }
    tempfile example_do
    tempname source target
    file open `source' using `"`help_file'"', read text
    quietly file open `target' using `"`example_do'"', write text replace
    local found 0
    local closed 0
    local lines 0
    file read `source' line
    while !r(eof) {
        if !`found' {
            if strtrim(`"`macval(line)'"') == "{* example_start - `example_name'}{...}" {
                local found 1
            }
        }
        else {
            if strtrim(`"`macval(line)'"') == "{* example_end}{...}" {
                local closed 1
                continue, break
            }
            file write `target' `"`macval(line)'"' _n
            local ++lines
        }
        file read `source' line
    }
    file close `source'
    file close `target'
    if !`found' {
        di as error `"example `example_name' was not found in `using'"'
        exit 111
    }
    if !`closed' | !`lines' {
        di as error `"example `example_name' has no complete executable block"'
        exit 111
    }
    do `"`example_do'"'
end
