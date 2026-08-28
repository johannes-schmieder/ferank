{smcl}
{* *! version 0.1.0 28aug2026}{...}

{title:Title}

{pstd}{cmd:ferank postestimation} {hline 2} graph and numerical certificates

{title:Syntax}

{p 8 16 2}{cmd:estat components}

{p 8 16 2}{cmd:estat convergence}

{title:Description}

{pstd}
{cmd:estat components} reports canonical strongly connected component coverage
and the selection rule used by the preceding {cmd:ferank} estimate.

{pstd}
{cmd:estat convergence} reports the method-specific certificate: original
stationary-equation residuals for Sorkin, or likelihood, constrained gradient,
Newton-system residual, and linear route for Bradley--Terry.

{pstd}
Version 0.1 has no {cmd:predict} command.
