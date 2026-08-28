//! Public input, option, result, and diagnostic types.

/// One prepared positive or nonpositive directed-flow row before validation.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EdgeInput {
    /// Origin firm identifier.
    pub origin: f64,
    /// Destination firm identifier.
    pub destination: f64,
    /// Directed flow weight.
    pub flow: f64,
}

/// One worker-period observation before transition construction.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PanelObservation {
    /// Worker identifier.
    pub worker: f64,
    /// Firm identifier; `None` is an observed missing firm and breaks a chain.
    pub firm: Option<f64>,
    /// Period value.
    pub time: f64,
}

/// Graph-construction options.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GraphOptions {
    /// Minimum aggregated directed flow retained as an edge.
    pub min_flow: f64,
}

impl Default for GraphOptions {
    fn default() -> Self {
        Self { min_flow: 0.0 }
    }
}

/// Estimation component request.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ComponentSelection {
    /// Largest component by firms, retained flow, then smallest firm ID.
    Largest,
    /// One-based component in deterministic reported order.
    Number(usize),
    /// Estimate every qualifying component independently.
    All,
}

/// Score normalization rule.
#[derive(Debug, Clone, PartialEq)]
pub enum Normalization {
    /// Unweighted mean score zero.
    Mean,
    /// Weighted mean score zero; weights align with the selected graph firms.
    Weighted(Vec<f64>),
    /// Set one external firm identifier's score to zero.
    Reference(f64),
}

impl Default for Normalization {
    fn default() -> Self {
        Self::Mean
    }
}

/// Shared numerical controls.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SolverOptions {
    /// Acceptance tolerance for original-equation certificates.
    pub tolerance: f64,
    /// Maximum outer iterations.
    pub max_iterations: usize,
    /// Requested deterministic worker count (`0` selects one in the core).
    pub threads: usize,
}

impl Default for SolverOptions {
    fn default() -> Self {
        Self {
            tolerance: 1e-10,
            max_iterations: 20_000,
            threads: 0,
        }
    }
}

/// Sorkin-specific controls.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SorkinOptions {
    /// Shared numerical controls.
    pub solver: SolverOptions,
    /// Lazy-transition weight in `(0, 1]`.
    pub lazy: f64,
}

impl Default for SorkinOptions {
    fn default() -> Self {
        Self {
            solver: SolverOptions::default(),
            lazy: 0.5,
        }
    }
}

/// Bradley--Terry-specific controls.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BradleyTerryOptions {
    /// Shared numerical controls.
    pub solver: SolverOptions,
    /// Largest system routed through the independent dense Newton step.
    pub dense_limit: usize,
    /// Maximum inner PCG iterations for larger systems.
    pub pcg_max_iterations: usize,
}

impl Default for BradleyTerryOptions {
    fn default() -> Self {
        Self {
            solver: SolverOptions::default(),
            dense_limit: 512,
            pcg_max_iterations: 10_000,
        }
    }
}

/// Ranking method.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Method {
    /// Sorkin stationary-flow value.
    Sorkin,
    /// Bradley--Terry pairwise likelihood.
    BradleyTerry,
}

/// One canonical directed edge using compact firm indices.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Edge {
    /// Compact origin index.
    pub origin: usize,
    /// Compact destination index.
    pub destination: usize,
    /// Aggregated positive flow.
    pub flow: f64,
}

/// Deterministic strongly connected component summary.
#[derive(Debug, Clone, PartialEq)]
pub struct ComponentSummary {
    /// One-based component identifier in reported order.
    pub id: usize,
    /// Number of firms.
    pub firms: usize,
    /// Number of retained directed edges internal to the component.
    pub edges: usize,
    /// Total retained directed flow internal to the component.
    pub flow: f64,
    /// Smallest external firm identifier under total numeric order.
    pub minimum_firm_id: f64,
}

/// Accounting from raw input to a canonical graph.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct GraphAccounting {
    /// Raw marked input rows.
    pub input_rows: usize,
    /// Raw positive non-self edge rows before duplicate aggregation.
    pub informative_rows: usize,
    /// Rows excluded for zero flow.
    pub zero_flow_rows: usize,
    /// Rows excluded because origin equals destination.
    pub self_move_rows: usize,
    /// Aggregated directed pairs removed by `min_flow`.
    pub below_min_flow_edges: usize,
    /// Constructed panel moves.
    pub valid_moves: usize,
    /// Panel same-firm continuations.
    pub same_firm_continuations: usize,
    /// Panel transitions broken by excessive gaps.
    pub gap_breaks: usize,
    /// Panel chains broken by observed missing firms.
    pub missing_firm_breaks: usize,
    /// Distinct workers in panel mode.
    pub workers: usize,
}

/// Canonical graph shared by both estimators.
#[derive(Debug, Clone, PartialEq)]
pub struct CanonicalGraph {
    /// Stable external firm identifiers in compact-index order.
    pub firm_ids: Vec<f64>,
    /// Aggregated positive directed edges in `(origin, destination)` order.
    pub edges: Vec<Edge>,
    /// Incoming flow per firm.
    pub inflow: Vec<f64>,
    /// Outgoing flow per firm.
    pub outflow: Vec<f64>,
    /// Distinct incoming-neighbor count per firm.
    pub in_degree: Vec<usize>,
    /// Distinct outgoing-neighbor count per firm.
    pub out_degree: Vec<usize>,
    /// One-based deterministic component assignment per firm.
    pub component_id: Vec<usize>,
    /// Components in deterministic reported order.
    pub components: Vec<ComponentSummary>,
    /// Input and filtering accounting.
    pub accounting: GraphAccounting,
}

/// Method-independent firm-level result.
#[derive(Debug, Clone, PartialEq)]
pub struct FirmResult {
    /// External firm identifier.
    pub firm_id: f64,
    /// One-based deterministic component identifier.
    pub component_id: usize,
    /// Normalized score (`log(q)` or Bradley--Terry `theta`).
    pub score: f64,
    /// One is the highest rank; exact ties receive their midrank.
    pub rank: f64,
    /// Within-component percentile on a zero-to-100 scale.
    pub percentile: f64,
    /// Incoming flow.
    pub inflow: f64,
    /// Outgoing flow.
    pub outflow: f64,
    /// Incoming degree.
    pub in_degree: usize,
    /// Outgoing degree.
    pub out_degree: usize,
    /// Sorkin revealed value `q`, when applicable.
    pub revealed_value_q: Option<f64>,
    /// Sorkin stationary mass, when applicable.
    pub stationary_mass: Option<f64>,
    /// Firm-level original-equation residual, when applicable.
    pub fixed_point_residual: Option<f64>,
}

/// Method-specific convergence evidence.
#[derive(Debug, Clone, PartialEq)]
pub enum Diagnostics {
    /// Sorkin fixed-point evidence.
    Sorkin {
        /// Iterations executed.
        iterations: usize,
        /// Lazy-transition weight.
        lazy: f64,
        /// Maximum absolute residual against `P*pi = pi`.
        residual_max: f64,
        /// L1 residual against `P*pi = pi`.
        residual_l1: f64,
        /// Maximum score difference under the deterministic alternative start.
        alternative_start_difference: f64,
        /// Effective deterministic thread route.
        threads: usize,
    },
    /// Bradley--Terry likelihood/KKT evidence.
    BradleyTerry {
        /// Newton iterations executed.
        iterations: usize,
        /// Accepted log likelihood.
        log_likelihood: f64,
        /// Total backtracking line-search reductions.
        line_search_steps: usize,
        /// Maximum absolute constrained gradient.
        gradient_max: f64,
        /// Maximum final Newton-system residual.
        newton_residual: f64,
        /// Linear-system route.
        linear_route: String,
        /// Effective deterministic thread route.
        threads: usize,
    },
}

/// Complete result for one or more requested components.
#[derive(Debug, Clone, PartialEq)]
pub struct EstimateResult {
    /// Ranking method.
    pub method: Method,
    /// Firm-level rows, grouped by component and ordered by external firm ID.
    pub firms: Vec<FirmResult>,
    /// Per-component numerical evidence in result-component order.
    pub diagnostics: Vec<Diagnostics>,
    /// Shared canonical graph accounting.
    pub graph: CanonicalGraph,
}
