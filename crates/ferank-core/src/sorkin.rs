//! Certified Sorkin stationary-flow rankings.

use crate::error::{invalid, invalid_data, no_convergence, Result};
use crate::graph::selected_subgraphs;
use crate::model::{
    CanonicalGraph, ComponentSelection, Diagnostics, EstimateResult, FirmResult, Method,
    Normalization, SorkinOptions,
};
use crate::rank::{compensated_sum, midranks, normalize_scores};

/// Estimate Sorkin scores on the requested strongly connected component(s).
///
/// # Errors
///
/// Returns an error for invalid controls, an ineligible component, invalid
/// normalization, or a fixed-point certificate that does not pass.
pub fn estimate_sorkin(
    graph: &CanonicalGraph,
    selection: ComponentSelection,
    normalization: &Normalization,
    options: SorkinOptions,
) -> Result<EstimateResult> {
    validate_options(options)?;
    let selected = selected_subgraphs(graph, selection)?;
    let mut firms = Vec::new();
    let mut diagnostics = Vec::new();
    for (component_id, subgraph) in selected {
        let local_normalization = local_normalization(graph, &subgraph, normalization)?;
        let solved = solve_component(&subgraph, options)?;
        let mut scores: Vec<f64> = solved
            .stationary_mass
            .iter()
            .zip(&subgraph.outflow)
            .map(|(&mass, &outflow)| (mass / outflow).ln())
            .collect();
        normalize_scores(&mut scores, &subgraph.firm_ids, &local_normalization)?;

        let alternative = stationary_solve(
            &subgraph,
            options,
            Some(alternative_start(subgraph.firm_ids.len())),
        )?;
        let mut alternative_scores: Vec<f64> = alternative
            .stationary_mass
            .iter()
            .zip(&subgraph.outflow)
            .map(|(&mass, &outflow)| (mass / outflow).ln())
            .collect();
        normalize_scores(
            &mut alternative_scores,
            &subgraph.firm_ids,
            &local_normalization,
        )?;
        let alternative_difference = scores
            .iter()
            .zip(&alternative_scores)
            .map(|(left, right)| (left - right).abs())
            .fold(0.0_f64, f64::max);
        let alternative_gate = options.solver.tolerance.sqrt().max(1e-11);
        if alternative_difference > alternative_gate {
            return Err(no_convergence(format!(
                "Sorkin alternative starts disagree by {alternative_difference:e}"
            )));
        }

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
                revealed_value_q: Some(solved.stationary_mass[index] / subgraph.outflow[index]),
                stationary_mass: Some(solved.stationary_mass[index]),
                fixed_point_residual: Some(solved.residual[index]),
            });
        }
        diagnostics.push(Diagnostics::Sorkin {
            iterations: solved.iterations,
            lazy: options.lazy,
            residual_max: solved.residual_max,
            residual_l1: solved.residual_l1,
            alternative_start_difference: alternative_difference,
            threads: effective_threads(options.solver.threads, subgraph.firm_ids.len()),
        });
    }
    Ok(EstimateResult {
        method: Method::Sorkin,
        firms,
        diagnostics,
        graph: graph.clone(),
    })
}

#[derive(Debug)]
struct StationaryResult {
    stationary_mass: Vec<f64>,
    residual: Vec<f64>,
    residual_max: f64,
    residual_l1: f64,
    iterations: usize,
}

fn solve_component(graph: &CanonicalGraph, options: SorkinOptions) -> Result<StationaryResult> {
    stationary_solve(graph, options, None)
}

fn stationary_solve(
    graph: &CanonicalGraph,
    options: SorkinOptions,
    start: Option<Vec<f64>>,
) -> Result<StationaryResult> {
    let firms = graph.firm_ids.len();
    if firms < 2 || graph.outflow.iter().any(|value| *value <= 0.0) {
        return Err(invalid_data(
            "Sorkin estimation requires positive outflow in a multi-firm SCC",
        ));
    }
    let mut mass = start.unwrap_or_else(|| vec![1.0 / firms as f64; firms]);
    normalize_probability(&mut mass)?;
    let incoming = incoming_layout(graph);
    let threads = effective_threads(options.solver.threads, firms);
    let mut iterations = 0;
    let mut final_residual = Vec::new();
    let mut final_max = f64::INFINITY;
    let mut final_l1 = f64::INFINITY;
    for iteration in 1..=options.solver.max_iterations {
        let transitioned = transition_product(&incoming, &mass, threads);
        let mut next = vec![0.0; firms];
        for index in 0..firms {
            next[index] = (1.0 - options.lazy) * mass[index] + options.lazy * transitioned[index];
        }
        normalize_probability(&mut next)?;
        let difference = next
            .iter()
            .zip(&mass)
            .map(|(left, right)| (left - right).abs())
            .fold(0.0_f64, f64::max);
        mass = next;
        iterations = iteration;
        if difference <= options.solver.tolerance || iteration % 25 == 0 {
            let (residual, maximum, l1) = certificate(&incoming, &mass, threads);
            final_residual = residual;
            final_max = maximum;
            final_l1 = l1;
            if maximum <= options.solver.tolerance && l1 <= options.solver.tolerance {
                break;
            }
        }
    }
    if final_residual.is_empty() {
        (final_residual, final_max, final_l1) = certificate(&incoming, &mass, threads);
    }
    if final_max > options.solver.tolerance || final_l1 > options.solver.tolerance {
        return Err(no_convergence(format!(
            "Sorkin fixed-point certificate failed after {iterations} iterations: max={final_max:e}, l1={final_l1:e}"
        )));
    }
    Ok(StationaryResult {
        stationary_mass: mass,
        residual: final_residual,
        residual_max: final_max,
        residual_l1: final_l1,
        iterations,
    })
}

fn incoming_layout(graph: &CanonicalGraph) -> Vec<Vec<(usize, f64)>> {
    let mut incoming = vec![Vec::new(); graph.firm_ids.len()];
    for edge in &graph.edges {
        incoming[edge.destination].push((edge.origin, edge.flow / graph.outflow[edge.origin]));
    }
    incoming
}

fn transition_product(incoming: &[Vec<(usize, f64)>], mass: &[f64], threads: usize) -> Vec<f64> {
    let mut result = vec![0.0; mass.len()];
    let chunk_size = mass.len().div_ceil(threads);
    std::thread::scope(|scope| {
        for (chunk_index, output) in result.chunks_mut(chunk_size).enumerate() {
            let start = chunk_index * chunk_size;
            let input = &incoming[start..(start + output.len())];
            scope.spawn(move || {
                for (slot, edges) in output.iter_mut().zip(input) {
                    let mut sum = 0.0;
                    let mut correction = 0.0;
                    for &(origin, probability) in edges {
                        compensated_add(&mut sum, &mut correction, probability * mass[origin]);
                    }
                    *slot = sum + correction;
                }
            });
        }
    });
    result
}

fn certificate(
    incoming: &[Vec<(usize, f64)>],
    mass: &[f64],
    threads: usize,
) -> (Vec<f64>, f64, f64) {
    let transitioned = transition_product(incoming, mass, threads);
    let residual: Vec<f64> = transitioned
        .iter()
        .zip(mass)
        .map(|(next, current)| next - current)
        .collect();
    let maximum = residual
        .iter()
        .map(|value| value.abs())
        .fold(0.0_f64, f64::max);
    let absolute: Vec<f64> = residual.iter().map(|value| value.abs()).collect();
    let l1 = compensated_sum(&absolute);
    (residual, maximum, l1)
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

fn normalize_probability(values: &mut [f64]) -> Result<()> {
    if values
        .iter()
        .any(|value| !value.is_finite() || *value < 0.0)
    {
        return Err(no_convergence(
            "Sorkin iteration produced invalid stationary mass",
        ));
    }
    let total = compensated_sum(values);
    if !total.is_finite() || total <= 0.0 {
        return Err(no_convergence(
            "Sorkin iteration produced zero or nonfinite mass",
        ));
    }
    for value in values {
        *value /= total;
    }
    Ok(())
}

fn alternative_start(firms: usize) -> Vec<f64> {
    let mut values: Vec<f64> = (1..=firms).map(|value| value as f64).collect();
    let total = compensated_sum(&values);
    for value in &mut values {
        *value /= total;
    }
    values
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

fn validate_options(options: SorkinOptions) -> Result<()> {
    if !options.solver.tolerance.is_finite() || options.solver.tolerance <= 0.0 {
        return Err(invalid("tolerance must be positive and finite"));
    }
    if options.solver.max_iterations == 0 {
        return Err(invalid("max_iterations must be positive"));
    }
    if !options.lazy.is_finite() || options.lazy <= 0.0 || options.lazy > 1.0 {
        return Err(invalid("lazy must lie in (0, 1]"));
    }
    Ok(())
}

const fn effective_threads(requested: usize, firms: usize) -> usize {
    if requested == 0 {
        1
    } else if requested < firms {
        requested
    } else {
        firms
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
                    destination: 3.0,
                    flow: 3.0,
                },
                EdgeInput {
                    origin: 3.0,
                    destination: 1.0,
                    flow: 2.0,
                },
                EdgeInput {
                    origin: 2.0,
                    destination: 1.0,
                    flow: 1.0,
                },
                EdgeInput {
                    origin: 3.0,
                    destination: 2.0,
                    flow: 1.0,
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
    fn fixed_point_is_certified_and_centered() {
        let result = estimate_sorkin(
            &fixture(),
            ComponentSelection::Largest,
            &Normalization::Mean,
            SorkinOptions::default(),
        )
        .unwrap();
        let mean =
            result.firms.iter().map(|row| row.score).sum::<f64>() / result.firms.len() as f64;
        assert!(mean.abs() < 1e-12);
        match &result.diagnostics[0] {
            Diagnostics::Sorkin { residual_max, .. } => assert!(*residual_max <= 1e-10),
            Diagnostics::BradleyTerry { .. } => panic!("wrong diagnostics"),
        }
    }
}
