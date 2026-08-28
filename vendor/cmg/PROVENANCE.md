# CMG provenance

The large-system Bradley--Terry preconditioner is adapted from the owner's
tracked GPL-3.0-only CMG implementation with this immutable identity:

- repository: `johannes-schmieder/vckss`
- commit: `5f6e3d4da84f638e866baca2c0c7707205d2182b`
- public module path: `rust/crates/vckss-core/src/cmg.rs`
- Git blob: `0bc4dfc8da7e7d8cc5de2389ade69280b0dc52a6`
- SHA-256: `54571c61a85a4fb74f090bb93f41489ed225f4a7784be01f03b697656b0d053a`
- license: GPL-3.0-only

An exact unmodified copy of that public module is retained at
`original/cmg.rs`; its Git blob and SHA-256 match the values above.

The source implementation builds a deterministic multilevel hierarchy and
symmetric V-cycle for a worker-eliminated hybrid graph. `ferank-core/src/cmg.rs`
adapts the registered hierarchy ideas to the ordinary connected Laplacian that
appears in each Bradley--Terry Newton step: normalized heavy-edge pairing,
deterministic coarse-edge aggregation, symmetric weighted-Jacobi smoothing, a
zero-sum quotient, and a dense constrained terminal solve. It deliberately
does not copy the source project's worker/problem types or uncommitted files.

The adaptation is part of the GPL-3.0-only corresponding source. Any material
change to its hierarchy, V-cycle symmetry, source identity, or licensing must
update this record and repeat numerical qualification.
