*! ferank 0.1.0 28aug2026
program define ferank, eclass sortpreserve
    version 18.0

    if substr(strtrim(`"`0'"'), 1, 1) == "," {
        syntax , [VERSION SELFTEST]
        local actions = (`"`version'"' != "") + (`"`selftest'"' != "")
        if `actions' != 1 {
            di as error "specify exactly one of version or selftest"
            exit 198
        }
        if `"`version'"' != "" _ferank_load, action(version)
        else _ferank_load, action(selftest)
        ereturn clear
        ereturn local cmd "ferank"
        ereturn local version "0.1.0"
        exit
    }

    syntax varlist(min=1 max=2) [if] [in], METHOD(string) ///
        [FLOW(varname) WORKER(varname) TIME(varname) MAXGAP(real 1) ///
        COMPONENT(string) NORMALIZE(string) NORMWEIGHT(varname) ///
        REFERENCE(string) MINFLOW(real 0) FRAME(string) REPLACE ///
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
    if `"`frame'"' == "" local frame "ferank_results"

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

    capture frame `frame': count
    local target_exists = (_rc == 0)
    if `target_exists' & `"`replace'"' == "" {
        di as error "result frame `frame' already exists; specify replace"
        exit 110
    }

    marksample touse, novarlist
    quietly count if `touse'
    if r(N) == 0 error 2000
    local marked_rows = r(N)

    tempname work shared_label firm_label worker_label
    tempvar input1 input2 input3 input4 output_firm output_score output_rank ///
        output_percentile output_inflow output_outflow output_indegree ///
        output_outdegree output_q output_pi output_residual output_component ///
        normalization_weight decoded_firm

    local copyvars "`varlist' `flow' `worker' `time' `normweight' `touse'"
    local copyvars : list uniq copyvars
    frame put `copyvars' if `touse', into(`work')

    if `firm1_string' {
        if `panel' {
            frame `work': encode `firm1', generate(`input2') label(`firm_label')
        }
        else {
            frame `work': encode `firm1', generate(`input2') label(`shared_label')
            frame `work': encode `firm2', generate(`input3') label(`shared_label')
        }
    }
    else {
        frame `work': generate double `input2' = `firm1'
        if !`panel' frame `work': generate double `input3' = `firm2'
    }

    if `panel' {
        if `worker_string' frame `work': encode `worker', generate(`input3') label(`worker_label')
        else frame `work': generate double `input3' = `worker'
        frame `work': generate double `input4' = `time'
    }
    else {
        if `"`flow'"' == "" frame `work': generate double `input4' = 1
        else frame `work': generate double `input4' = `flow'
    }
    if `"`normweight'"' == "" frame `work': generate double `normalization_weight' = 1
    else frame `work': generate double `normalization_weight' = `normweight'

    local capacity = cond(`panel', `marked_rows', 2 * `marked_rows')
    frame `work': set obs `capacity'
    frame `work': replace `touse' = 0 if missing(`touse')
    foreach variable in `output_firm' `output_score' `output_rank' ///
        `output_percentile' `output_inflow' `output_outflow' `output_indegree' ///
        `output_outdegree' `output_q' `output_pi' `output_residual' `output_component' {
        frame `work': generate double `variable' = .
    }
    frame `work': replace `normalization_weight' = 1 if missing(`touse')

    _ferank_load, action(loadonly)
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
    frame `work': keep in 1/`n_results'
    frame `work': keep `output_firm' `output_score' `output_rank' ///
        `output_percentile' `output_inflow' `output_outflow' `output_indegree' ///
        `output_outdegree' `output_q' `output_pi' `output_residual' `output_component'
    if `firm1_string' {
        local result_label = cond(`panel', "`firm_label'", "`shared_label'")
        frame `work': label values `output_firm' `result_label'
        frame `work': decode `output_firm', generate(`decoded_firm')
        frame `work': drop `output_firm'
        frame `work': rename `decoded_firm' firm_id
    }
    else frame `work': rename `output_firm' firm_id
    frame `work': rename `output_score' score
    frame `work': rename `output_rank' rank
    frame `work': rename `output_percentile' percentile
    frame `work': rename `output_inflow' inflow
    frame `work': rename `output_outflow' outflow
    frame `work': rename `output_indegree' in_degree
    frame `work': rename `output_outdegree' out_degree
    frame `work': rename `output_q' revealed_value_q
    frame `work': rename `output_pi' stationary_mass
    frame `work': rename `output_residual' fixed_point_residual
    frame `work': rename `output_component' component_id
    frame `work': generate str16 method = "`method'"
    frame `work': generate byte in_estimation_component = 1
    frame `work': order firm_id method component_id in_estimation_component ///
        score rank percentile inflow outflow in_degree out_degree ///
        revealed_value_q stationary_mass fixed_point_residual

    if `target_exists' frame drop `frame'
    frame rename `work' `frame'

    ereturn clear
    ereturn local cmd "ferank"
    ereturn local estat_cmd "ferank_estat"
    ereturn local cmdline `"ferank `0'"'
    ereturn local method "`method'"
    ereturn local input_mode "`input_mode'"
    ereturn local component "`component'"
    ereturn local normalization "`normalize'"
    ereturn local engine "`engine'"
    ereturn local result_frame "`frame'"
    ereturn local convergence_certificate "`_ferank_certificate'"
    ereturn local linear_route "`_ferank_linear_route'"
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

    di as text "Firm-flow ranking (`method')"
    di as text "  result frame: " as result "`frame'"
    di as text "  firms/edges/components: " as result %10.0fc e(N_results) ///
        " / " %10.0fc e(N_edges) " / " %10.0fc e(N_components)
    di as text "  convergence certificate: " as result "success"
end
