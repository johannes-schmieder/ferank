*! ferank postestimation 0.1.0 28aug2026
program define ferank_estat
    version 18.0
    if `"`e(cmd)'"' != "ferank" error 301
    gettoken subcommand 0 : 0, parse(" ,")
    local subcommand = lower(strtrim(`"`subcommand'"'))
    if `"`subcommand'"' == "components" {
        syntax [, *]
        di as text "Canonical graph components"
        di as text "  total components: " as result %10.0fc e(N_components)
        di as text "  requested rule:  " as result "`e(component)'"
        di as text "  result firms:     " as result %10.0fc e(N_results)
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
