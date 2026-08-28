//! Certified Bradley--Terry rankings from directed worker moves.

use crate::cmg::{CmgPreconditioner, CmgReceipt, WeightedEdge};
use crate::error::{invalid, invalid_data, no_convergence, Result};
use crate::graph::selected_subgraphs;
use crate::model::{
    BradleyTerryOptions, CanonicalGraph, ComponentSelection, Diagnostics, EstimateResult,
    FirmResult, Method, Normalization,
};
use crate::rank::{compensated_sum, midranks, normalize_scores};

/// Estimate Bradley--Terry scores on the requested strongly connected component(s).
///
/// # Errors
///
/// Returns an error for invalid controls, an ineligible component, invalid
/// normalization, or a likelihood/KKT certificate that does not pass.
pub fn estimate_bradley_terry(
    graph: &CanonicalGraph,
    selection: ComponentSelection,
    normalization: &Normalization,
    options: BradleyTerryOptions,
) -> Result<EstimateResult> {
    validate_options(options)?;
    let selected = selected_subgraphs(graph, selection)?;
    let mut firms = Vec::new();
    let mut diagnostics = Vec::new();
    for (component_id, subgraph) in selected {
        let local_normalization = local_normalization(graph, &subgraph, normalization)?;
        let solved = solve_component(&subgraph, options)?;
        let mut scores = solved.theta;
        normalize_scores(&mut scores, &subgraph.firm_ids, &local_normalization)?;
        let (ranks, percentiles) = midranks(&scores);
        for index in 0..subgraph.firm_ids.len() {
            firms.push(FirmResult {
                firm_id: subgraph.firm_ids[index],
                component_id,
                score: scores[index],
                rank: ranks[index],
                percentile: percentiles[index],
                inflow: subgraph.inflow[index],
                outflow: subgraph.outflow[index],
                in_degree: subgraph.in_degree[index],
                out_degree: subgraph.out_degree[index],
                revealed_value_q: None,
                stationary_mass: None,
                fixed_point_residual: None,
            });
        }
        diagnostics.push(Diagnostics::BradleyTerry {
            iterations: solved.iterations,
            log_likelihood: solved.log_likelihood,
            line_search_steps: solved.line_search_steps,
            gradient_max: solved.gradient_max,
            newton_residual: solved.newton_residual,
            linear_route: solved.linear_route,
            threads: solved.threads,
        });
    }
    Ok(EstimateResult {
        method: Method::BradleyTerry,
        firms,
        diagnostics,
        graph: graph.clone(),
    })
}

#[derive(Debug)]
struct BradleyTerrySolve {
    theta: Vec<f64>,
    iterations: usize,
    log_likelihood: f64,
    line_search_steps: usize,
    gradient_max: f64,
    newton_residual: f64,
    linear_route: String,
    threads: usize,
}

fn solve_component(
    graph: &CanonicalGraph,
    options: BradleyTerryOptions,
) -> Result<BradleyTerrySolve> {
    let firms = graph.firm_ids.len();
    if firms < 2 || graph.edges.is_empty() {
        return Err(invalid_data(
            "Bradley--Terry estimation requires a multi-firm comparison graph",
        ));
    }
    let mut route = if firms <= options.dense_limit {
        "dense-kkt".to_owned()
    } else {
        "pcg-cmg-adapter".to_owned()
    };
    let structure = BtStructure::new(graph);
    let threads = effective_threads(options.solver.threads, graph.edges.len().max(firms));
    let mut theta = vec![0.0; firms];
    let mut evaluation = evaluate(graph, &structure, &theta, threads);
    let mut total_line_search_steps = 0;
    let mut newton_residual = 0.0;
    let mut iterations = 0;
    let mut last_likelihood_change = 0.0_f64;

    for iteration in 0..=options.solver.max_iterations {
        iterations = iteration;
        let gradient_max = maximum_centered(&evaluation.gradient);
        let likelihood_gate = options.solver.tolerance * (1.0 + evaluation.log_likelihood.abs());
        if gradient_max <= options.solver.tolerance
            && last_likelihood_change.abs() <= likelihood_gate
        {
            return Ok(BradleyTerrySolve {
                theta,
                iterations,
                log_likelihood: evaluation.log_likelihood,
                line_search_steps: total_line_search_steps,
                gradient_max,
                newton_residual,
                linear_route: route,
                threads,
            });
        }
        if iteration == options.solver.max_iterations {
            break;
        }

        let linear = if firms <= options.dense_limit {
            solve_dense_step(graph, &evaluation.edge_curvature, &evaluation.gradient)?
        } else {
            solve_pcg_step(
                graph,
                &evaluation.edge_curvature,
                &evaluation.gradient,
                options.solver.tolerance.clamp(1e-14, 1e-12),
                options.pcg_max_iterations,
            )?
        };
        newton_residual = linear.residual_max;
        if let Some(receipt) = linear.cmg_receipt {
            route = format!(
                "pcg-cmg(levels={},terminal={},edge_complexity={:.3})",
                receipt.levels, receipt.terminal_vertices, receipt.edge_complexity
            );
        }
        let directional = dot(&evaluation.gradient, &linear.step);
        if !directional.is_finite() || directional <= 0.0 {
            return Err(no_convergence(
                "Bradley--Terry Newton direction is not an ascent direction",
            ));
        }

        let mut alpha = 1.0;
        let mut accepted = None;
        for reduction in 0..=60 {
            let mut candidate: Vec<f64> = theta
                .iter()
                .zip(&linear.step)
                .map(|(value, step)| value + alpha * step)
                .collect();
            center(&mut candidate);
            let candidate_evaluation = evaluate(graph, &structure, &candidate, threads);
            if candidate_evaluation.log_likelihood.is_finite()
                && candidate_evaluation.log_likelihood
                    >= evaluation.log_likelihood + 1e-4 * alpha * directional
            {
                accepted = Some((candidate, candidate_evaluation, reduction));
                break;
            }
            alpha *= 0.5;
        }
        let Some((candidate, candidate_evaluation, reductions)) = accepted else {
            return Err(no_convergence(
                "Bradley--Terry line search failed to increase the likelihood",
            ));
        };
        total_line_search_steps += reductions;
        last_likelihood_change = candidate_evaluation.log_likelihood - evaluation.log_likelihood;
        theta = candidate;
        evaluation = candidate_evaluation;
    }

    Err(no_convergence(format!(
        "Bradley--Terry certificate failed after {iterations} iterations: gradient={:e}",
        maximum_centered(&evaluation.gradient)
    )))
}

#[derive(Debug)]
struct Evaluation {
    log_likelihood: f64,
    gradient: Vec<f64>,
    edge_curvature: Vec<f64>,
}

#[derive(Debug, Clone, Copy)]
struct IncidentEdge {
    edge: usize,
    sign: f64,
}

#[derive(Debug)]
struct BtStructure {
    incident: Vec<Vec<IncidentEdge>>,
}

impl BtStructure {
    fn new(graph: &CanonicalGraph) -> Self {
        let mut incident = vec![Vec::new(); graph.firm_ids.len()];
        for (index, edge) in graph.edges.iter().enumerate() {
            incident[edge.origin].push(IncidentEdge {
                edge: index,
                sign: -1.0,
            });
            incident[edge.destination].push(IncidentEdge {
                edge: index,
                sign: 1.0,
            });
        }
        Self { incident }
    }
}

fn evaluate(
    graph: &CanonicalGraph,
    structure: &BtStructure,
    theta: &[f64],
    threads: usize,
) -> Evaluation {
    let mut log_terms = vec![0.0; graph.edges.len()];
    let mut edge_score = vec![0.0; graph.edges.len()];
    let mut edge_curvature = vec![0.0; graph.edges.len()];
    let edge_threads = effective_threads(threads, graph.edges.len());
    let edge_chunk = graph.edges.len().div_ceil(edge_threads);
    std::thread::scope(|scope| {
        for (chunk_index, ((logs, scores), curvatures)) in log_terms
            .chunks_mut(edge_chunk)
            .zip(edge_score.chunks_mut(edge_chunk))
            .zip(edge_curvature.chunks_mut(edge_chunk))
            .enumerate()
        {
            let start = chunk_index * edge_chunk;
            let edges = &graph.edges[start..(start + logs.len())];
            scope.spawn(move || {
                for (((log_term, score), curvature), edge) in
                    logs.iter_mut().zip(scores).zip(curvatures).zip(edges)
                {
                    let difference = theta[edge.destination] - theta[edge.origin];
                    let probability = logistic(difference);
                    *log_term = edge.flow * log_logistic(difference);
                    *score = edge.flow * (1.0 - probability);
                    *curvature = edge.flow * probability * (1.0 - probability);
                }
            });
        }
    });

    let mut gradient = vec![0.0; theta.len()];
    let firm_threads = effective_threads(threads, theta.len());
    let firm_chunk = theta.len().div_ceil(firm_threads);
    std::thread::scope(|scope| {
        for (chunk_index, output) in gradient.chunks_mut(firm_chunk).enumerate() {
            let start = chunk_index * firm_chunk;
            let incident = &structure.incident[start..(start + output.len())];
            let edge_score = &edge_score;
            scope.spawn(move || {
                for (slot, firm_edges) in output.iter_mut().zip(incident) {
                    let mut sum = 0.0;
                    let mut correction = 0.0;
                    for item in firm_edges {
                        compensated_add(
                            &mut sum,
                            &mut correction,
                            item.sign * edge_score[item.edge],
                        );
                    }
                    *slot = sum + correction;
                }
            });
        }
    });
    center(&mut gradient);
    Evaluation {
        log_likelihood: compensated_sum(&log_terms),
        gradient,
        edge_curvature,
    }
}

#[derive(Debug)]
struct LinearStep {
    step: Vec<f64>,
    residual_max: f64,
    cmg_receipt: Option<CmgReceipt>,
}

fn solve_dense_step(
    graph: &CanonicalGraph,
    edge_curvature: &[f64],
    gradient: &[f64],
) -> Result<LinearStep> {
    let firms = gradient.len();
    let dimension = firms + 1;
    let mut matrix = vec![0.0; dimension * dimension];
    for (edge, &curvature) in graph.edges.iter().zip(edge_curvature) {
        add_matrix(&mut matrix, dimension, edge.origin, edge.origin, curvature);
        add_matrix(
            &mut matrix,
            dimension,
            edge.destination,
            edge.destination,
            curvature,
        );
        add_matrix(
            &mut matrix,
            dimension,
            edge.origin,
            edge.destination,
            -curvature,
        );
        add_matrix(
            &mut matrix,
            dimension,
            edge.destination,
            edge.origin,
            -curvature,
        );
    }
    for firm in 0..firms {
        matrix[firm * dimension + firms] = 1.0;
        matrix[firms * dimension + firm] = 1.0;
    }
    let mut right_hand_side = vec![0.0; dimension];
    right_hand_side[..firms].copy_from_slice(gradient);
    let solution = gaussian_solve(matrix, right_hand_side, dimension)?;
    let mut step = solution[..firms].to_vec();
    center(&mut step);
    let residual_max = laplacian_residual(graph, edge_curvature, &step, gradient);
    Ok(LinearStep {
        step,
        residual_max,
        cmg_receipt: None,
    })
}

fn solve_pcg_step(
    graph: &CanonicalGraph,
    edge_curvature: &[f64],
    gradient: &[f64],
    tolerance: f64,
    max_iterations: usize,
) -> Result<LinearStep> {
    let firms = gradient.len();
    let mut diagonal = vec![0.0; firms];
    for (edge, &curvature) in graph.edges.iter().zip(edge_curvature) {
        diagonal[edge.origin] += curvature;
        diagonal[edge.destination] += curvature;
    }
    if diagonal
        .iter()
        .any(|value| !value.is_finite() || *value <= 0.0)
    {
        return Err(no_convergence(
            "Bradley--Terry Laplacian has an invalid diagonal",
        ));
    }
    let cmg_edges: Vec<WeightedEdge> = graph
        .edges
        .iter()
        .zip(edge_curvature)
        .map(|(edge, &weight)| WeightedEdge {
            left: edge.origin,
            right: edge.destination,
            weight,
        })
        .collect();
    let cmg = CmgPreconditioner::build(firms, cmg_edges)?;
    let cmg_receipt = cmg.receipt();
    let mut step = vec![0.0; firms];
    let mut residual = gradient.to_vec();
    center(&mut residual);
    let mut preconditioned = cmg.apply(&residual)?;
    center(&mut preconditioned);
    let mut direction = preconditioned.clone();
    let mut residual_dot = dot(&residual, &preconditioned);
    let gate = tolerance
        * gradient
            .iter()
            .map(|value| value.abs())
            .fold(1.0_f64, f64::max);
    for _ in 0..max_iterations {
        let product = laplacian_product(graph, edge_curvature, &direction);
        let denominator = dot(&direction, &product);
        if !denominator.is_finite() || denominator <= 0.0 {
            return Err(no_convergence(
                "Bradley--Terry PCG encountered nonpositive curvature",
            ));
        }
        let alpha = residual_dot / denominator;
        for index in 0..firms {
            step[index] += alpha * direction[index];
            residual[index] -= alpha * product[index];
        }
        center(&mut step);
        center(&mut residual);
        let residual_max = residual
            .iter()
            .map(|value| value.abs())
            .fold(0.0_f64, f64::max);
        if residual_max <= gate {
            return Ok(LinearStep {
                step,
                residual_max,
                cmg_receipt: Some(cmg_receipt),
            });
        }
        preconditioned = cmg.apply(&residual)?;
        center(&mut preconditioned);
        let next_dot = dot(&residual, &preconditioned);
        let beta = next_dot / residual_dot;
        for index in 0..firms {
            direction[index] = preconditioned[index] + beta * direction[index];
        }
        center(&mut direction);
        residual_dot = next_dot;
    }
    Err(no_convergence(
        "Bradley--Terry PCG did not meet its linear-system certificate",
    ))
}

fn laplacian_product(graph: &CanonicalGraph, curvature: &[f64], vector: &[f64]) -> Vec<f64> {
    let mut product = vec![0.0; vector.len()];
    for (edge, &weight) in graph.edges.iter().zip(curvature) {
        let difference = weight * (vector[edge.origin] - vector[edge.destination]);
        product[edge.origin] += difference;
        product[edge.destination] -= difference;
    }
    product
}

fn laplacian_residual(
    graph: &CanonicalGraph,
    edge_curvature: &[f64],
    step: &[f64],
    gradient: &[f64],
) -> f64 {
    laplacian_product(graph, edge_curvature, step)
        .iter()
        .zip(gradient)
        .map(|(left, right)| (left - right).abs())
        .fold(0.0_f64, f64::max)
}

fn gaussian_solve(mut matrix: Vec<f64>, mut rhs: Vec<f64>, dimension: usize) -> Result<Vec<f64>> {
    for column in 0..dimension {
        let pivot = (column..dimension)
            .max_by(|&left, &right| {
                matrix[left * dimension + column]
                    .abs()
                    .total_cmp(&matrix[right * dimension + column].abs())
            })
            .unwrap_or(column);
        let pivot_value = matrix[pivot * dimension + column].abs();
        if !pivot_value.is_finite() || pivot_value <= 1e-15 {
            return Err(no_convergence(
                "Bradley--Terry dense KKT system is numerically singular",
            ));
        }
        if pivot != column {
            for index in column..dimension {
                matrix.swap(column * dimension + index, pivot * dimension + index);
            }
            rhs.swap(column, pivot);
        }
        let diagonal = matrix[column * dimension + column];
        for row in (column + 1)..dimension {
            let factor = matrix[row * dimension + column] / diagonal;
            matrix[row * dimension + column] = 0.0;
            for index in (column + 1)..dimension {
                matrix[row * dimension + index] -= factor * matrix[column * dimension + index];
            }
            rhs[row] -= factor * rhs[column];
        }
    }
    let mut solution = vec![0.0; dimension];
    for row in (0..dimension).rev() {
        let mut value = rhs[row];
        for column in (row + 1)..dimension {
            value -= matrix[row * dimension + column] * solution[column];
        }
        solution[row] = value / matrix[row * dimension + row];
    }
    if solution.iter().any(|value| !value.is_finite()) {
        return Err(no_convergence(
            "Bradley--Terry dense KKT solve produced nonfinite values",
        ));
    }
    Ok(solution)
}

fn add_matrix(matrix: &mut [f64], dimension: usize, row: usize, column: usize, value: f64) {
    matrix[row * dimension + column] += value;
}

fn logistic(value: f64) -> f64 {
    if value >= 0.0 {
        1.0 / (1.0 + (-value).exp())
    } else {
        let exponential = value.exp();
        exponential / (1.0 + exponential)
    }
}

fn log_logistic(value: f64) -> f64 {
    if value >= 0.0 {
        -(-value).exp().ln_1p()
    } else {
        value - value.exp().ln_1p()
    }
}

fn center(values: &mut [f64]) {
    let mean = compensated_sum(values) / values.len() as f64;
    for value in values {
        *value -= mean;
    }
}

fn maximum_centered(values: &[f64]) -> f64 {
    let mean = compensated_sum(values) / values.len() as f64;
    values
        .iter()
        .map(|value| (value - mean).abs())
        .fold(0.0_f64, f64::max)
}

fn dot(left: &[f64], right: &[f64]) -> f64 {
    let products: Vec<f64> = left
        .iter()
        .zip(right)
        .map(|(left, right)| left * right)
        .collect();
    compensated_sum(&products)
}

fn compensated_add(sum: &mut f64, compensation: &mut f64, value: f64) {
    let updated = *sum + value;
    if sum.abs() >= value.abs() {
        *compensation += (*sum - updated) + value;
    } else {
        *compensation += (value - updated) + *sum;
    }
    *sum = updated;
}

fn local_normalization(
    full: &CanonicalGraph,
    selected: &CanonicalGraph,
    normalization: &Normalization,
) -> Result<Normalization> {
    match normalization {
        Normalization::Weighted(weights) if weights.len() == full.firm_ids.len() => {
            let mut selected_weights = Vec::with_capacity(selected.firm_ids.len());
            for &firm in &selected.firm_ids {
                let position = full
                    .firm_ids
                    .iter()
                    .position(|candidate| candidate.total_cmp(&firm).is_eq())
                    .ok_or_else(|| invalid("selected firm is absent from the full graph"))?;
                selected_weights.push(weights[position]);
            }
            Ok(Normalization::Weighted(selected_weights))
        }
        other => Ok(other.clone()),
    }
}

fn validate_options(options: BradleyTerryOptions) -> Result<()> {
    if !options.solver.tolerance.is_finite() || options.solver.tolerance <= 0.0 {
        return Err(invalid("tolerance must be positive and finite"));
    }
    if options.solver.max_iterations == 0 {
        return Err(invalid("max_iterations must be positive"));
    }
    if options.dense_limit < 2 {
        return Err(invalid("dense_limit must be at least two"));
    }
    if options.pcg_max_iterations == 0 {
        return Err(invalid("pcg_max_iterations must be positive"));
    }
    Ok(())
}

const fn effective_threads(requested: usize, work_items: usize) -> usize {
    if requested == 0 {
        1
    } else if requested < work_items {
        requested
    } else {
        work_items
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::graph::canonicalize_edges;
    use crate::model::{EdgeInput, GraphOptions};

    fn fixture() -> CanonicalGraph {
        canonicalize_edges(
            &[
                EdgeInput {
                    origin: 1.0,
                    destination: 2.0,
                    flow: 4.0,
                },
                EdgeInput {
                    origin: 2.0,
                    destination: 1.0,
                    flow: 1.0,
                },
                EdgeInput {
                    origin: 2.0,
                    destination: 3.0,
                    flow: 3.0,
                },
                EdgeInput {
                    origin: 3.0,
                    destination: 2.0,
                    flow: 1.0,
                },
                EdgeInput {
                    origin: 3.0,
                    destination: 1.0,
                    flow: 2.0,
                },
                EdgeInput {
                    origin: 1.0,
                    destination: 3.0,
                    flow: 1.0,
                },
            ],
            GraphOptions::default(),
        )
        .unwrap()
    }

    #[test]
    fn newton_solution_has_a_kkt_certificate() {
        let result = estimate_bradley_terry(
            &fixture(),
            ComponentSelection::Largest,
            &Normalization::Mean,
            BradleyTerryOptions::default(),
        )
        .unwrap();
        let mean =
            result.firms.iter().map(|row| row.score).sum::<f64>() / result.firms.len() as f64;
        assert!(mean.abs() < 1e-12);
        match &result.diagnostics[0] {
            Diagnostics::BradleyTerry { gradient_max, .. } => {
                assert!(*gradient_max <= 1e-10);
            }
            Diagnostics::Sorkin { .. } => panic!("wrong diagnostics"),
        }
    }

    #[test]
    fn balanced_two_firm_scores_tie() {
        let graph = canonicalize_edges(
            &[
                EdgeInput {
                    origin: 1.0,
                    destination: 2.0,
                    flow: 5.0,
                },
                EdgeInput {
                    origin: 2.0,
                    destination: 1.0,
                    flow: 5.0,
                },
            ],
            GraphOptions::default(),
        )
        .unwrap();
        let result = estimate_bradley_terry(
            &graph,
            ComponentSelection::Largest,
            &Normalization::Mean,
            BradleyTerryOptions::default(),
        )
        .unwrap();
        assert_eq!(result.firms[0].score, result.firms[1].score);
        assert_eq!(result.firms[0].rank, 1.5);
    }

    #[test]
    fn logistic_primitives_are_finite_at_extreme_logits() {
        for value in [-1_000.0, -100.0, 0.0, 100.0, 1_000.0] {
            assert!(logistic(value).is_finite());
            assert!(log_logistic(value).is_finite());
            assert!((0.0..=1.0).contains(&logistic(value)));
            assert!(log_logistic(value) <= 0.0);
        }
    }

    #[test]
    fn highly_imbalanced_comparisons_remain_finite() {
        let graph = canonicalize_edges(
            &[
                EdgeInput {
                    origin: 1.0,
                    destination: 2.0,
                    flow: 100_000_000.0,
                },
                EdgeInput {
                    origin: 2.0,
                    destination: 1.0,
                    flow: 1.0,
                },
            ],
            GraphOptions::default(),
        )
        .unwrap();
        let result = estimate_bradley_terry(
            &graph,
            ComponentSelection::Largest,
            &Normalization::Mean,
            BradleyTerryOptions {
                solver: crate::model::SolverOptions {
                    tolerance: 1e-8,
                    ..crate::model::SolverOptions::default()
                },
                ..BradleyTerryOptions::default()
            },
        )
        .unwrap();
        assert!(result.firms.iter().all(|row| row.score.is_finite()));
        assert!(result.firms[1].score > result.firms[0].score);
    }
}
