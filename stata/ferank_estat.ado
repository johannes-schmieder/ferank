*! ferank postestimation 0.1.0 28aug2026
program define ferank_estat
    version 18.0
    if `"`e(cmd)'"' != "ferank" error 301
    gettoken subcommand 0 : 0, parse(" ,")
    local subcommand = lower(strtrim(`"`subcommand'"'))
    if `"`subcommand'"' == "components" {
        syntax [, *]
        di as text _n "Graph coverage and component selection"
        di as text "{hline 64}"
        di as text "Canonical graph firms" _col(37) as result %12.0fc e(N_firms)
        di as text "Canonical directed edges" _col(37) as result %12.0fc e(N_edges)
        di as text "Graph components (all sizes)" _col(37) as result %12.0fc e(N_components)
        di as text "Selection rule" _col(37) as result "`e(component)'"
        di as text "Estimated components" _col(37) as result %12.0fc e(N_components_estimated)
        di as text "Ranked firms" _col(37) as result %12.0fc e(N_results)
        di as text "Input rows" _col(37) as result %12.0fc e(N_input)
        di as text "Rows with all input firms ranked" _col(37) as result %12.0fc e(N_mapped)
        di as text "Remaining selected rows" _col(37) as result %12.0fc e(N_unmapped)
        if `"`e(input_mode)'"' == "edge" {
            di as text "Rows with ranked origin" _col(37) as result %12.0fc e(N_mapped_origin)
            di as text "Rows with ranked destination" _col(37) as result %12.0fc e(N_mapped_destination)
        }
        di as text "{hline 64}"
        di as text "Graph counts precede selection; mapped rows describe attached firm values."
    }
    else if `"`subcommand'"' == "convergence" {
        syntax [, *]
        di as text "Numerical convergence certificate"
        di as text "  method:       " as result "`e(method)'"
        di as text "  status:       " as result "`e(convergence_certificate)'"
        di as text "  iterations:   " as result %10.0fc e(iterations)
        if `"`e(method)'"' == "sorkin" {
            di as text "  max residual: " as result %12.4e e(residual_max)
            di as text "  L1 residual:  " as result %12.4e e(residual_l1)
        }
        else {
            di as text "  log likelihood: " as result %12.6g e(ll)
            di as text "  max gradient:   " as result %12.4e e(gradient_max)
            di as text "  Newton residual:" as result %12.4e e(newton_residual)
            di as text "  linear route:   " as result "`e(linear_route)'"
        }
    }
    else {
        di as error "estat `subcommand' is not supported after ferank"
        exit 321
    }
end
