//! Bounded dense reference engines kept independent of production graph assembly.
//!
//! Inputs use the mathematical convention `flow[destination][origin]`.

use crate::error::{invalid, invalid_data, no_convergence, Result};
use crate::graph::selected_subgraphs;
use crate::model::{
    CanonicalGraph, ComponentSelection, Diagnostics, EstimateResult, FirmResult, Method,
    Normalization,
};
use crate::rank::{compensated_sum, midranks, normalize_scores};

/// Run the bounded independent dense engine on selected components.
///
/// # Errors
///
/// Returns an error for an ineligible or oversized component, invalid
/// normalization, or a failed dense numerical certificate.
pub fn estimate_reference(
    graph: &CanonicalGraph,
    method: Method,
    selection: ComponentSelection,
    normalization: &Normalization,
    tolerance: f64,
    max_iterations: usize,
) -> Result<EstimateResult> {
    let selected = selected_subgraphs(graph, selection)?;
    let mut firms = Vec::new();
    let mut diagnostics = Vec::new();
    for (component_id, subgraph) in selected {
        if subgraph.firm_ids.len() > 2_048 {
            return Err(invalid(
                "reference engine is limited to 2,048 firms per component",
            ));
        }
        let flow = dense_matrix(&subgraph);
        let local_normalization = local_normalization(graph, &subgraph, normalization)?;
        match method {
            Method::Sorkin => {
                let raw_scores = dense_sorkin(&flow, tolerance)?;
                let unnormalized_mass: Vec<f64> = raw_scores
                    .iter()
                    .zip(&subgraph.outflow)
                    .map(|(score, outflow)| score.exp() * outflow)
                    .collect();
                let mass_total = compensated_sum(&unnormalized_mass);
                let stationary_mass: Vec<f64> = unnormalized_mass
                    .iter()
                    .map(|value| value / mass_total)
                    .collect();
                let revealed_q: Vec<f64> = stationary_mass
                    .iter()
                    .zip(&subgraph.outflow)
                    .map(|(mass, outflow)| mass / outflow)
                    .collect();
                let residual =
                    dense_stationary_residual(&flow, &stationary_mass, &subgraph.outflow);
                let residual_max = residual
                    .iter()
                    .map(|value| value.abs())
                    .fold(0.0_f64, f64::max);
                let residual_l1 =
                    compensated_sum(&residual.iter().map(|value| value.abs()).collect::<Vec<_>>());
                let mut scores = raw_scores;
                normalize_scores(&mut scores, &subgraph.firm_ids, &local_normalization)?;
                let (ranks, percentiles) = midranks(&scores);
                for index in 0..subgraph.firm_ids.len() {
                    firms.push(firm_result(
                        &subgraph,
                        component_id,
                        index,
                        scores[index],
                        ranks[index],
                        percentiles[index],
                        Some(revealed_q[index]),
                        Some(stationary_mass[index]),
                        Some(residual[index]),
                    ));
                }
                diagnostics.push(Diagnostics::Sorkin {
                    iterations: 1,
                    lazy: 0.0,
                    residual_max,
                    residual_l1,
                    alternative_start_difference: 0.0,
                    threads: 1,
                });
            }
            Method::BradleyTerry => {
                let mut scores = dense_bradley_terry(&flow, tolerance, max_iterations)?;
                let (log_likelihood, gradient_max) = dense_bt_certificate(&flow, &scores);
                normalize_scores(&mut scores, &subgraph.firm_ids, &local_normalization)?;
                let (ranks, percentiles) = midranks(&scores);
                for index in 0..subgraph.firm_ids.len() {
                    firms.push(firm_result(
                        &subgraph,
                        component_id,
                        index,
                        scores[index],
                        ranks[index],
                        percentiles[index],
                        None,
                        None,
                        None,
                    ));
                }
                diagnostics.push(Diagnostics::BradleyTerry {
                    iterations: 0,
                    log_likelihood,
                    line_search_steps: 0,
                    gradient_max,
                    newton_residual: 0.0,
                    linear_route: "reference-dense-kkt".to_owned(),
                    threads: 1,
                });
            }
        }
    }
    Ok(EstimateResult {
        method,
        firms,
        diagnostics,
        graph: graph.clone(),
    })
}

/// Solve the dense Sorkin stationary system and return mean-zero `log(q)`.
///
/// # Errors
///
/// Returns an error for an invalid dense flow matrix or a failed stationary
/// equation certificate.
pub fn dense_sorkin(flow: &[Vec<f64>], tolerance: f64) -> Result<Vec<f64>> {
    validate_dense_flow(flow)?;
    if !tolerance.is_finite() || tolerance <= 0.0 {
        return Err(invalid("reference tolerance must be positive and finite"));
    }
    let firms = flow.len();
    let mut outflow = vec![0.0; firms];
    for (origin, value) in outflow.iter_mut().enumerate() {
        *value = compensated_sum(
            &(0..firms)
                .map(|destination| flow[destination][origin])
                .collect::<Vec<_>>(),
        );
        if *value <= 0.0 {
            return Err(invalid_data(
                "dense Sorkin reference requires positive outflow",
            ));
        }
    }
    let mut system = vec![vec![0.0; firms]; firms];
    let mut rhs = vec![0.0; firms];
    for row in 0..(firms - 1) {
        for (column, &column_outflow) in outflow.iter().enumerate() {
            system[row][column] = flow[row][column] / column_outflow - f64::from(row == column);
        }
    }
    system[firms - 1].fill(1.0);
    rhs[firms - 1] = 1.0;
    let mass = dense_gaussian(system, rhs)?;
    if mass.iter().any(|value| !value.is_finite() || *value <= 0.0) {
        return Err(no_convergence(
            "dense Sorkin reference produced nonpositive mass",
        ));
    }
    let mut residual_max = 0.0_f64;
    for destination in 0..firms {
        let next = (0..firms)
            .map(|origin| flow[destination][origin] * mass[origin] / outflow[origin])
            .sum::<f64>();
        residual_max = residual_max.max((next - mass[destination]).abs());
    }
    if residual_max > tolerance * firms as f64 {
        return Err(no_convergence(format!(
            "dense Sorkin reference residual is {residual_max:e}"
        )));
    }
    let mut scores: Vec<f64> = mass
        .iter()
        .zip(outflow)
        .map(|(mass, outflow)| (mass / outflow).ln())
        .collect();
    mean_center(&mut scores);
    Ok(scores)
}

/// Solve the bounded dense Bradley--Terry likelihood and return mean-zero scores.
///
/// # Errors
///
/// Returns an error for invalid inputs, a singular constrained Newton system,
/// or failure to meet the bounded likelihood certificate.
pub fn dense_bradley_terry(
    flow: &[Vec<f64>],
    tolerance: f64,
    max_iterations: usize,
) -> Result<Vec<f64>> {
    validate_dense_flow(flow)?;
    if !tolerance.is_finite() || tolerance <= 0.0 || max_iterations == 0 {
        return Err(invalid("invalid dense Bradley--Terry controls"));
    }
    let firms = flow.len();
    let mut theta = vec![0.0; firms];
    for _ in 0..max_iterations {
        let (likelihood, gradient, information) = dense_bt_evaluate(flow, &theta);
        let gradient_max = gradient
            .iter()
            .map(|value| value.abs())
            .fold(0.0_f64, f64::max);
        if gradient_max <= tolerance {
            mean_center(&mut theta);
            return Ok(theta);
        }
        let dimension = firms + 1;
        let mut system = vec![vec![0.0; dimension]; dimension];
        let mut rhs = vec![0.0; dimension];
        for row in 0..firms {
            for column in 0..firms {
                system[row][column] = information[row][column];
            }
            system[row][firms] = 1.0;
            system[firms][row] = 1.0;
            rhs[row] = gradient[row];
        }
        let solution = dense_gaussian(system, rhs)?;
        let direction = &solution[..firms];
        let ascent = gradient
            .iter()
            .zip(direction)
            .map(|(left, right)| left * right)
            .sum::<f64>();
        let mut step = 1.0;
        let mut accepted = false;
        for _ in 0..60 {
            let mut candidate: Vec<f64> = theta
                .iter()
                .zip(direction)
                .map(|(value, direction)| value + step * direction)
                .collect();
            mean_center(&mut candidate);
            let candidate_likelihood = dense_bt_evaluate(flow, &candidate).0;
            if candidate_likelihood >= likelihood + 1e-4 * step * ascent {
                theta = candidate;
                accepted = true;
                break;
            }
            step *= 0.5;
        }
        if !accepted {
            return Err(no_convergence(
                "dense Bradley--Terry reference line search failed",
            ));
        }
    }
    Err(no_convergence(
        "dense Bradley--Terry reference exhausted its iteration limit",
    ))
}

fn validate_dense_flow(flow: &[Vec<f64>]) -> Result<()> {
    let firms = flow.len();
    if firms < 2 || flow.iter().any(|row| row.len() != firms) {
        return Err(invalid(
            "dense flow input must be a square matrix of dimension at least two",
        ));
    }
    for (row, values) in flow.iter().enumerate() {
        for (column, &value) in values.iter().enumerate() {
            if !value.is_finite() || value < 0.0 {
                return Err(invalid_data(
                    "dense flow entries must be nonnegative and finite",
                ));
            }
            if row == column && value != 0.0 {
                return Err(invalid_data("dense flow diagonal must be zero"));
            }
        }
    }
    Ok(())
}

fn dense_bt_evaluate(flow: &[Vec<f64>], theta: &[f64]) -> (f64, Vec<f64>, Vec<Vec<f64>>) {
    let firms = theta.len();
    let mut likelihood = 0.0;
    let mut gradient = vec![0.0; firms];
    let mut information = vec![vec![0.0; firms]; firms];
    for destination in 0..firms {
        for origin in 0..firms {
            let count = flow[destination][origin];
            if count == 0.0 || destination == origin {
                continue;
            }
            let difference = theta[destination] - theta[origin];
            let probability = if difference >= 0.0 {
                1.0 / (1.0 + (-difference).exp())
            } else {
                let exponential = difference.exp();
                exponential / (1.0 + exponential)
            };
            likelihood += count
                * if difference >= 0.0 {
                    -(-difference).exp().ln_1p()
                } else {
                    difference - difference.exp().ln_1p()
                };
            let score = count * (1.0 - probability);
            gradient[destination] += score;
            gradient[origin] -= score;
            let curvature = count * probability * (1.0 - probability);
            information[destination][destination] += curvature;
            information[origin][origin] += curvature;
            information[destination][origin] -= curvature;
            information[origin][destination] -= curvature;
        }
    }
    let mean = gradient.iter().sum::<f64>() / firms as f64;
    for value in &mut gradient {
        *value -= mean;
    }
    (likelihood, gradient, information)
}

fn dense_gaussian(mut matrix: Vec<Vec<f64>>, mut rhs: Vec<f64>) -> Result<Vec<f64>> {
    let dimension = rhs.len();
    for column in 0..dimension {
        let pivot = (column..dimension)
            .max_by(|&left, &right| {
                matrix[left][column]
                    .abs()
                    .total_cmp(&matrix[right][column].abs())
            })
            .unwrap_or(column);
        if matrix[pivot][column].abs() <= 1e-15 {
            return Err(no_convergence("dense reference system is singular"));
        }
        matrix.swap(column, pivot);
        rhs.swap(column, pivot);
        for row in (column + 1)..dimension {
            let factor = matrix[row][column] / matrix[column][column];
            for index in column..dimension {
                matrix[row][index] -= factor * matrix[column][index];
            }
            rhs[row] -= factor * rhs[column];
        }
    }
    let mut solution = vec![0.0; dimension];
    for row in (0..dimension).rev() {
        let trailing = ((row + 1)..dimension)
            .map(|column| matrix[row][column] * solution[column])
            .sum::<f64>();
        solution[row] = (rhs[row] - trailing) / matrix[row][row];
    }
    Ok(solution)
}

fn mean_center(values: &mut [f64]) {
    let mean = values.iter().sum::<f64>() / values.len() as f64;
    for value in values {
        *value -= mean;
    }
}

fn dense_matrix(graph: &CanonicalGraph) -> Vec<Vec<f64>> {
    let mut flow = vec![vec![0.0; graph.firm_ids.len()]; graph.firm_ids.len()];
    for edge in &graph.edges {
        flow[edge.destination][edge.origin] = edge.flow;
    }
    flow
}

fn dense_stationary_residual(flow: &[Vec<f64>], mass: &[f64], outflow: &[f64]) -> Vec<f64> {
    (0..mass.len())
        .map(|destination| {
            (0..mass.len())
                .map(|origin| flow[destination][origin] * mass[origin] / outflow[origin])
                .sum::<f64>()
                - mass[destination]
        })
        .collect()
}

fn dense_bt_certificate(flow: &[Vec<f64>], theta: &[f64]) -> (f64, f64) {
    let (log_likelihood, gradient, _) = dense_bt_evaluate(flow, theta);
    let gradient_max = gradient
        .iter()
        .map(|value| value.abs())
        .fold(0.0_f64, f64::max);
    (log_likelihood, gradient_max)
}

#[allow(clippy::too_many_arguments)]
fn firm_result(
    graph: &CanonicalGraph,
    component_id: usize,
    index: usize,
    score: f64,
    rank: f64,
    percentile: f64,
    revealed_value_q: Option<f64>,
    stationary_mass: Option<f64>,
    fixed_point_residual: Option<f64>,
) -> FirmResult {
    FirmResult {
        firm_id: graph.firm_ids[index],
        component_id,
        score,
        rank,
        percentile,
        inflow: graph.inflow[index],
        outflow: graph.outflow[index],
        in_degree: graph.in_degree[index],
        out_degree: graph.out_degree[index],
        revealed_value_q,
        stationary_mass,
        fixed_point_residual,
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bradley_terry::estimate_bradley_terry;
    use crate::graph::canonicalize_edges;
    use crate::model::{
        BradleyTerryOptions, ComponentSelection, EdgeInput, GraphOptions, Normalization,
    };
    use crate::sorkin::estimate_sorkin;

    fn inputs() -> Vec<EdgeInput> {
        vec![
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
        ]
    }

    fn matrix(rows: &[EdgeInput]) -> Vec<Vec<f64>> {
        let mut flow = vec![vec![0.0; 3]; 3];
        for row in rows {
            let origin = match row.origin {
                1.0 => 0,
                2.0 => 1,
                3.0 => 2,
                _ => unreachable!(),
            };
            let destination = match row.destination {
                1.0 => 0,
                2.0 => 1,
                3.0 => 2,
                _ => unreachable!(),
            };
            flow[destination][origin] += row.flow;
        }
        flow
    }

    #[test]
    fn production_sorkin_matches_independent_dense_system() {
        let rows = inputs();
        let graph = canonicalize_edges(&rows, GraphOptions::default()).unwrap();
        let production = estimate_sorkin(
            &graph,
            ComponentSelection::Largest,
            &Normalization::Mean,
            crate::model::SorkinOptions::default(),
        )
        .unwrap();
        let reference = dense_sorkin(&matrix(&rows), 1e-10).unwrap();
        for (row, expected) in production.firms.iter().zip(reference) {
            assert!((row.score - expected).abs() < 1e-8);
        }
    }

    #[test]
    fn production_bradley_terry_matches_independent_dense_newton() {
        let rows = inputs();
        let graph = canonicalize_edges(&rows, GraphOptions::default()).unwrap();
        let production = estimate_bradley_terry(
            &graph,
            ComponentSelection::Largest,
            &Normalization::Mean,
            BradleyTerryOptions::default(),
        )
        .unwrap();
        let reference = dense_bradley_terry(&matrix(&rows), 1e-11, 100).unwrap();
        for (row, expected) in production.firms.iter().zip(reference) {
            assert!((row.score - expected).abs() < 1e-8);
        }
    }
}
