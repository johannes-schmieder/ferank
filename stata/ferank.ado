*! ferank 0.1.0 30sep2026
program define ferank, eclass sortpreserve
    version 18.0

    if substr(strtrim(`"`0'"'), 1, 1) == "," {
        syntax , [VERSION SELFTEST]
        local actions = (`"`version'"' != "") + (`"`selftest'"' != "")
        if `actions' != 1 {
            di as error "specify exactly one of version or selftest"
            exit 198
        }
        if `"`version'"' != "" ferank_load, action(version)
        else ferank_load, action(selftest)
        ereturn clear
        ereturn local cmd "ferank"
        ereturn local version "0.1.0"
        exit
    }

    * A private scratch frame is always removed, including on failed solves.
    tempname work
    local caller_frame "`c(frame)'"
    if c(noisily) capture noisily _ferank_fit `0' _work(`work')
    else capture _ferank_fit `0' _work(`work')
    local fit_rc = _rc
    frame change `caller_frame'
    capture frame drop `work'
    if `fit_rc' exit `fit_rc'
    ereturn local cmdline `"ferank `0'"'
end

program define _ferank_fit, eclass
    version 18.0

    syntax varlist(min=1 max=2) [if] [in], METHOD(string) _WORK(name) ///
        [FLOW(varname) WORKER(varname) TIME(varname) MAXGAP(real 1) ///
        COMPONENT(string) NORMALIZE(string) NORMWEIGHT(varname) ///
        REFERENCE(string) MINFLOW(real 0) GENerate(namelist) SCORE(namelist) ///
        PERCENTile(namelist) COMPONENTID(namelist) ///
        TOLERANCE(real 1e-10) MAXITER(integer 20000) THREADS(integer 0) ///
        ENGINE(string) LAZY(real 0.5) VERBOSE]

    if `"`reference'"' == "" local reference "."
    local method = lower(strtrim(`"`method'"'))
    foreach numeric_option in `flow' `time' `normweight' {
        if `"`numeric_option'"' != "" {
            capture confirm numeric variable `numeric_option'
            if _rc {
                di as error "`numeric_option' must be numeric"
                exit 109
            }
        }
    }
    if !inlist(`"`method'"', "sorkin", "bradleyterry") {
        di as error "method() must be sorkin or bradleyterry"
        exit 198
    }
    if `"`component'"' == "" local component "largest"
    local component = lower(strtrim(`"`component'"'))
    if `"`normalize'"' == "" local normalize "mean"
    local normalize = lower(strtrim(`"`normalize'"'))
    if !inlist(`"`normalize'"', "mean", "weighted", "reference") {
        di as error "normalize() must be mean, weighted, or reference"
        exit 198
    }
    if `"`normalize'"' == "weighted" & `"`normweight'"' == "" {
        di as error "normalize(weighted) requires normweight()"
        exit 198
    }
    if `"`normalize'"' == "reference" {
        capture confirm number `reference'
        if _rc | missing(`reference') {
            di as error "normalize(reference) requires a finite numeric reference()"
            exit 198
        }
    }
    if `"`engine'"' == "" local engine "plugin"
    local engine = lower(strtrim(`"`engine'"'))
    if !inlist(`"`engine'"', "plugin", "reference") {
        di as error "engine() must be plugin or reference"
        exit 198
    }
    if `minflow' < 0 | missing(`minflow') {
        di as error "minflow() must be nonnegative and finite"
        exit 198
    }
    if `tolerance' <= 0 | missing(`tolerance') | `maxiter' <= 0 | `threads' < 0 {
        di as error "invalid numerical controls"
        exit 198
    }
    if `lazy' <= 0 | `lazy' > 1 | missing(`lazy') {
        di as error "lazy() must lie in (0,1]"
        exit 198
    }

    local nvars : word count `varlist'
    local panel = (`"`worker'"' != "" | `"`time'"' != "")
    if `panel' {
        if `nvars' != 1 | `"`worker'"' == "" | `"`time'"' == "" {
            di as error "panel mode requires one firm variable and both worker() and time()"
            exit 198
        }
        if `"`flow'"' != "" {
            di as error "flow() is available only in prepared edge-list mode"
            exit 198
        }
        if `maxgap' <= 0 | missing(`maxgap') {
            di as error "maxgap() must be positive and finite"
            exit 198
        }
        local input_mode "panel"
    }
    else {
        if `nvars' != 2 {
            di as error "edge-list mode requires origin and destination variables"
            exit 198
        }
        local input_mode "edge"
    }
    if `"`generate'`score'`percentile'"' == "" {
        di as error "specify generate(), score(), or percentile()"
        exit 198
    }
    local requested "`generate' `score' `percentile' `componentid'"
    local unique : list uniq requested
    local n_requested : word count `requested'
    local n_unique : word count `unique'
    if `n_requested' != `n_unique' {
        di as error "each output variable must have a distinct name"
        exit 198
    }
    foreach option in generate score percentile componentid {
        if `"``option''"' != "" {
            local n_output : word count ``option''
            if `n_output' != `nvars' {
                if `panel' di as error "`option'() requires one new variable in panel mode"
                else di as error "`option'() requires two new variables: origin then destination"
                exit 198
            }
        }
    }
    confirm new variable `requested'
    local work "`_work'"

    local firm1 : word 1 of `varlist'
    local firm2 : word 2 of `varlist'
    capture confirm string variable `firm1'
    local firm1_string = (_rc == 0)
    if !`panel' {
        capture confirm string variable `firm2'
        local firm2_string = (_rc == 0)
        if `firm1_string' != `firm2_string' {
            di as error "origin and destination identifiers must have the same storage type"
            exit 109
        }
    }
    capture confirm string variable `worker'
    local worker_string = (`panel' & _rc == 0)

    marksample touse, novarlist
    quietly count if `touse'
    if r(N) == 0 error 2000
    local marked_rows = r(N)

    tempname shared_label firm_label worker_label
    tempvar input1 input2 input3 input4 output_firm output_score output_rank ///
        output_percentile output_inflow output_outflow output_indegree ///
        output_outdegree output_q output_pi output_residual output_component ///
        normalization_weight decoded_firm

    local copyvars "`varlist' `flow' `worker' `time' `normweight' `touse'"
    local copyvars : list uniq copyvars
    frame put `copyvars' if `touse', into(`work')

    if `firm1_string' {
        if `panel' {
            quietly frame `work': encode `firm1', generate(`input2') label(`firm_label')
        }
        else {
            quietly frame `work': encode `firm1', generate(`input2') label(`shared_label')
            quietly frame `work': encode `firm2', generate(`input3') label(`shared_label')
        }
    }
    else {
        quietly frame `work': generate double `input2' = `firm1'
        if !`panel' quietly frame `work': generate double `input3' = `firm2'
    }

    if `panel' {
        if `worker_string' quietly frame `work': encode `worker', generate(`input3') label(`worker_label')
        else quietly frame `work': generate double `input3' = `worker'
        quietly frame `work': generate double `input4' = `time'
    }
    else {
        if `"`flow'"' == "" quietly frame `work': generate double `input4' = 1
        else quietly frame `work': generate double `input4' = `flow'
    }
    if `"`normweight'"' == "" quietly frame `work': generate double `normalization_weight' = 1
    else quietly frame `work': generate double `normalization_weight' = `normweight'

    local capacity = cond(`panel', `marked_rows', 2 * `marked_rows')
    quietly frame `work': set obs `capacity'
    quietly frame `work': replace `touse' = 0 if missing(`touse')
    foreach variable in `output_firm' `output_score' `output_rank' ///
        `output_percentile' `output_inflow' `output_outflow' `output_indegree' ///
        `output_outdegree' `output_q' `output_pi' `output_residual' `output_component' {
        quietly frame `work': generate double `variable' = .
    }
    quietly frame `work': replace `normalization_weight' = 1 if missing(`touse')

    ferank_load, action(loadonly)
    local plugin_file `"`r(plugin_file)'"'
    local caller_frame "`c(frame)'"
    frame change `work'
    capture program __ferank_estimate_plugin, plugin using(`"`plugin_file'"')
    local load_rc = _rc
    if `load_rc' != 0 & `load_rc' != 110 {
        frame change `caller_frame'
        capture frame drop `work'
        exit `load_rc'
    }
    capture noisily plugin call __ferank_estimate_plugin `touse' `input2' `input3' `input4' ///
        `output_firm' `output_score' `output_rank' `output_percentile' ///
        `output_inflow' `output_outflow' `output_indegree' `output_outdegree' ///
        `output_q' `output_pi' `output_residual' `output_component' ///
        `normalization_weight', `"estimate-`input_mode'"' ///
        `"method=`method'"' `"component=`component'"' `"normalize=`normalize'"' ///
        `"reference=`reference'"' `"minflow=`minflow'"' `"maxgap=`maxgap'"' ///
        `"tolerance=`tolerance'"' `"maxiter=`maxiter'"' ///
        `"threads=`threads'"' `"lazy=`lazy'"' `"engine=`engine'"'
    local plugin_rc = _rc
    frame change `caller_frame'
    if `plugin_rc' != 0 {
        capture frame drop `work'
        exit `plugin_rc'
    }

    local n_results = scalar(__ferank_n_results)
    quietly frame `work': keep in 1/`n_results'
    quietly frame `work': keep `output_firm' `output_score' `output_rank' ///
        `output_percentile' `output_inflow' `output_outflow' `output_indegree' ///
        `output_outdegree' `output_q' `output_pi' `output_residual' `output_component'
    if `firm1_string' {
        local result_label = cond(`panel', "`firm_label'", "`shared_label'")
        quietly frame `work': label values `output_firm' `result_label'
        quietly frame `work': decode `output_firm', generate(`decoded_firm')
        quietly frame `work': drop `output_firm'
        quietly frame `work': rename `decoded_firm' firm_id
    }
    else quietly frame `work': rename `output_firm' firm_id
    quietly frame `work': rename `output_score' score
    quietly frame `work': rename `output_rank' rank
    quietly frame `work': rename `output_percentile' percentile
    quietly frame `work': rename `output_inflow' inflow
    quietly frame `work': rename `output_outflow' outflow
    quietly frame `work': rename `output_indegree' in_degree
    quietly frame `work': rename `output_outdegree' out_degree
    quietly frame `work': rename `output_q' revealed_value_q
    quietly frame `work': rename `output_pi' stationary_mass
    quietly frame `work': rename `output_residual' fixed_point_residual
    quietly frame `work': rename `output_component' component_id
    * Count distinct estimated components before mapping onto caller rows.
    tempvar component_tag
    quietly frame `work': egen byte `component_tag' = tag(component_id)
    quietly frame `work': count if `component_tag'
    local n_estimated = r(N)

    * Stage every requested value under temporary names.  No user variable
    * is created until the solve, all joins and all validations have succeeded.
    local staged_outputs ""
    local named_outputs ""
    forvalues endpoint = 1/`nvars' {
        local key : word `endpoint' of `varlist'
        tempvar link
        quietly frlink m:1 `key', frame(`work' firm_id) generate(`link')
        quietly count if `touse' & !missing(`link')
        local mapped`endpoint' = r(N)
        if `endpoint' == 1 local link1 "`link'"
        else local link2 "`link'"
        foreach option in generate score percentile componentid {
            if `"``option''"' != "" {
                local output_name : word `endpoint' of ``option''
                local source "`option'"
                if "`option'" == "generate" local source "rank"
                if "`option'" == "componentid" local source "component_id"
                tempvar staged
                quietly frget `staged'=`source', from(`link')
                quietly replace `staged' = . if !`touse'
                local description "continuous firm score (higher is better)"
                if "`option'" == "generate" local description "firm rank (1 is best; ties averaged)"
                if "`option'" == "percentile" local description "equal-firm percentile (100 is best)"
                if "`option'" == "componentid" local description "estimated flow component ID"
                local endpoint_label ""
                if !`panel' {
                    local endpoint_label "origin: "
                    if `endpoint' == 2 local endpoint_label "destination: "
                }
                label variable `staged' "`method' `endpoint_label'`description'"
                local staged_outputs "`staged_outputs' `staged'"
                local named_outputs "`named_outputs' `output_name'"
            }
        }
    }
    local mapped = `mapped1'
    if !`panel' {
        quietly count if `touse' & !missing(`link1', `link2')
        local mapped = r(N)
    }

    * Group rename is atomic; output names were checked before estimation.
    rename (`staged_outputs') (`named_outputs')

    ereturn clear
    ereturn local cmd "ferank"
    ereturn local estat_cmd "ferank_estat"
    ereturn local cmdline `"ferank `0'"'
    ereturn local method "`method'"
    ereturn local input_mode "`input_mode'"
    ereturn local component "`component'"
    ereturn local normalization "`normalize'"
    ereturn local engine "`engine'"
    ereturn local rankvars "`generate'"
    ereturn local scorevars "`score'"
    ereturn local percentilevars "`percentile'"
    ereturn local componentvars "`componentid'"
    ereturn local convergence_certificate "`_ferank_certificate'"
    ereturn local linear_route "`_ferank_linear_route'"
    ereturn scalar N_components_estimated = `n_estimated'
    ereturn scalar N_mapped = `mapped'
    ereturn scalar N_unmapped = `marked_rows' - `mapped'
    if !`panel' {
        ereturn scalar N_mapped_origin = `mapped1'
        ereturn scalar N_mapped_destination = `mapped2'
    }
    ereturn scalar tolerance = `tolerance'
    ereturn scalar maxiter = `maxiter'
    ereturn scalar N_input = scalar(__ferank_input_rows)
    ereturn scalar N_firms = scalar(__ferank_n_firms)
    ereturn scalar N_results = scalar(__ferank_n_results)
    ereturn scalar N_edges = scalar(__ferank_n_edges)
    ereturn scalar N_components = scalar(__ferank_n_components)
    ereturn scalar iterations = scalar(__ferank_iterations)
    ereturn scalar residual_max = scalar(__ferank_residual_max)
    ereturn scalar residual_l1 = scalar(__ferank_residual_l1)
    ereturn scalar ll = scalar(__ferank_loglikelihood)
    ereturn scalar gradient_max = scalar(__ferank_gradient_max)
    ereturn scalar newton_residual = scalar(__ferank_newton_residual)
    ereturn scalar line_search_steps = scalar(__ferank_line_search_steps)
    ereturn scalar threads = scalar(__ferank_threads)
    ereturn scalar time_input_graph = scalar(__ferank_time_input_graph)
    ereturn scalar time_solve_rank = scalar(__ferank_time_solve_rank)
    ereturn scalar time_store = scalar(__ferank_time_store)
    ereturn scalar time_total = scalar(__ferank_time_total)
    ereturn scalar valid_moves = scalar(__ferank_valid_moves)
    ereturn scalar gap_breaks = scalar(__ferank_gap_breaks)
    ereturn scalar missing_firm_breaks = scalar(__ferank_missing_breaks)
    ereturn scalar same_firm_continuations = scalar(__ferank_same_firm)

    _ferank_display
    if `"`verbose'"' != "" estat convergence
end

program define _ferank_display
    version 18.0
    local method "Sorkin"
    if `"`e(method)'"' == "bradleyterry" local method "Bradley-Terry"
    local mode "Worker-period panel"
    if `"`e(input_mode)'"' == "edge" local mode "Prepared directed flows"

    di as text _n "Firm rankings from worker flows" _col(49) "Method: " as result "`method'"
    di as text "{hline 78}"
    di as text "Input" _col(29) as result "`mode'" ///
        _col(55) as text "Input rows" _col(69) as result %10.0fc e(N_input)
    di as text "Component rule" _col(29) as result "`e(component)'" ///
        _col(55) as text "Graph firms" _col(69) as result %10.0fc e(N_firms)
    di as text "Score centering" _col(29) as result "`e(normalization)'" ///
        _col(55) as text "Ranked firms" _col(69) as result %10.0fc e(N_results)
    di as text "Engine / native threads" _col(29) as result "`e(engine)' / " %3.0f e(threads) ///
        _col(55) as text "Directed edges" _col(69) as result %10.0fc e(N_edges)
    di as text "Graph / fitted components" _col(29) as result %8.0fc e(N_components) ///
        " / " %8.0fc e(N_components_estimated)
    if `"`e(input_mode)'"' == "panel" {
        di as text "Panel moves / gap breaks" _col(29) as result %10.0fc e(valid_moves) ///
            " / " %10.0fc e(gap_breaks)
        di as text "Rows receiving firm values" _col(29) as result %10.0fc e(N_mapped) ///
            as text " of " as result %10.0fc e(N_input)
    }
    else {
        di as text "Mapped origin / destination" _col(29) as result %10.0fc e(N_mapped_origin) ///
            " / " %10.0fc e(N_mapped_destination)
        di as text "Rows with both firms ranked" _col(29) as result %10.0fc e(N_mapped) ///
            as text " of " as result %10.0fc e(N_input)
    }
    di as text "Convergence" _col(29) as result "`e(convergence_certificate)'" ///
        _col(55) as text "Iterations" _col(69) as result %10.0fc e(iterations)
    if `"`e(method)'"' == "sorkin" {
        di as text "Max / L1 equation residual" _col(29) as result %10.3e e(residual_max) ///
            " / " %10.3e e(residual_l1)
    }
    else {
        di as text "Constrained gradient" _col(29) as result %10.3e e(gradient_max) ///
            _col(55) as text "Log likelihood" _col(69) as result %10.3f e(ll)
    }
    di as text "Native elapsed seconds" _col(29) as result %10.4f e(time_total)
    di as text "{hline 78}"
    di as text "Generated variables"
    foreach statistic in rank score percentile component {
        local names `"`e(`statistic'vars)'"'
        local endpoint = 0
        foreach name of local names {
            local ++endpoint
            local suffix ""
            if `"`e(input_mode)'"' == "edge" {
                local suffix " (origin)"
                if `endpoint' == 2 local suffix " (destination)"
            }
            di as text "  `statistic'`suffix'" _col(29) as result "`name'"
        }
    }
    di as text "{hline 78}"
    di as text "Rank 1 is best; higher scores and percentiles are better. Ties are averaged."
    di as text "Missing: rows outside if/in and firms without an estimated rank."
    di as text "Native timing excludes Stata preparation and matching."
    if e(N_components_estimated) > 1 {
        di as text "Scores, ranks and percentiles are comparable only within each component."
        if `"`e(componentvars)'"' == "" ///
            di as text "Use componentid() to save component labels for comparisons."
    }
end
