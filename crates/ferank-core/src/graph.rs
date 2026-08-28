//! Deterministic input canonicalization and strongly connected components.

use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};

use crate::error::{invalid, invalid_data, no_observations, Result};
use crate::model::{
    CanonicalGraph, ComponentSelection, ComponentSummary, Edge, EdgeInput, GraphAccounting,
    GraphOptions, PanelObservation,
};

#[derive(Debug, Clone, Copy)]
struct FirmKey(f64);

impl FirmKey {
    fn new(value: f64, label: &str) -> Result<Self> {
        if !value.is_finite() {
            return Err(invalid_data(format!(
                "{label} firm identifier must be finite"
            )));
        }
        Ok(Self(if value == 0.0 { 0.0 } else { value }))
    }
}

impl PartialEq for FirmKey {
    fn eq(&self, other: &Self) -> bool {
        self.0.total_cmp(&other.0) == Ordering::Equal
    }
}

impl Eq for FirmKey {}

impl PartialOrd for FirmKey {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for FirmKey {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0.total_cmp(&other.0)
    }
}

#[derive(Debug, Clone, Copy)]
struct PreparedEdge {
    origin: FirmKey,
    destination: FirmKey,
    flow: f64,
}

#[derive(Clone, Copy)]
struct ValidatedObservation {
    worker: FirmKey,
    firm: Option<FirmKey>,
    time: f64,
}

/// Convert prepared edge rows into the canonical graph used by both methods.
///
/// # Errors
///
/// Returns an error for invalid identifiers or flows, an invalid `min_flow`,
/// or an input that leaves no positive non-self directed edges.
pub fn canonicalize_edges(rows: &[EdgeInput], options: GraphOptions) -> Result<CanonicalGraph> {
    validate_graph_options(options)?;
    if rows.is_empty() {
        return Err(no_observations("no directed-flow rows were supplied"));
    }

    let mut accounting = GraphAccounting {
        input_rows: rows.len(),
        ..GraphAccounting::default()
    };
    let mut prepared = Vec::with_capacity(rows.len());
    for row in rows {
        let origin = FirmKey::new(row.origin, "origin")?;
        let destination = FirmKey::new(row.destination, "destination")?;
        if !row.flow.is_finite() {
            return Err(invalid_data("flow weights must be finite"));
        }
        if row.flow < 0.0 {
            return Err(invalid_data("flow weights must be nonnegative"));
        }
        if row.flow == 0.0 {
            accounting.zero_flow_rows += 1;
            continue;
        }
        if origin == destination {
            accounting.self_move_rows += 1;
            continue;
        }
        accounting.informative_rows += 1;
        prepared.push(PreparedEdge {
            origin,
            destination,
            flow: row.flow,
        });
    }
    if prepared.is_empty() {
        return Err(no_observations(
            "no positive non-self directed flows remain",
        ));
    }

    prepared.sort_by(|left, right| {
        left.origin
            .cmp(&right.origin)
            .then_with(|| left.destination.cmp(&right.destination))
            .then_with(|| left.flow.total_cmp(&right.flow))
    });

    let mut aggregated = Vec::<PreparedEdge>::new();
    let mut cursor = 0;
    while cursor < prepared.len() {
        let origin = prepared[cursor].origin;
        let destination = prepared[cursor].destination;
        let mut sum = 0.0;
        let mut compensation = 0.0;
        while cursor < prepared.len()
            && prepared[cursor].origin == origin
            && prepared[cursor].destination == destination
        {
            neumaier_add(&mut sum, &mut compensation, prepared[cursor].flow);
            cursor += 1;
        }
        let flow = sum + compensation;
        if !flow.is_finite() || flow <= 0.0 {
            return Err(invalid_data(
                "aggregated directed flow is not positive and finite",
            ));
        }
        if flow < options.min_flow {
            accounting.below_min_flow_edges += 1;
        } else {
            aggregated.push(PreparedEdge {
                origin,
                destination,
                flow,
            });
        }
    }
    if aggregated.is_empty() {
        return Err(no_observations(
            "no directed edges remain after applying min_flow",
        ));
    }

    let mut firm_set = BTreeSet::new();
    for edge in &aggregated {
        firm_set.insert(edge.origin);
        firm_set.insert(edge.destination);
    }
    let firm_ids: Vec<f64> = firm_set.iter().map(|key| key.0).collect();
    let index: BTreeMap<FirmKey, usize> = firm_set
        .into_iter()
        .enumerate()
        .map(|(position, key)| (key, position))
        .collect();
    let edges: Vec<Edge> = aggregated
        .into_iter()
        .map(|edge| Edge {
            origin: index[&edge.origin],
            destination: index[&edge.destination],
            flow: edge.flow,
        })
        .collect();

    build_graph(firm_ids, edges, accounting)
}

/// Convert a narrow worker-period panel into the shared canonical graph.
///
/// # Errors
///
/// Returns an error for invalid worker, firm, time, or gap values; duplicate
/// worker-time observations; or a panel that constructs no valid moves.
pub fn canonicalize_panel(
    observations: &[PanelObservation],
    max_gap: f64,
    options: GraphOptions,
) -> Result<CanonicalGraph> {
    validate_graph_options(options)?;
    if !max_gap.is_finite() || max_gap <= 0.0 {
        return Err(invalid("max_gap must be positive and finite"));
    }
    if observations.is_empty() {
        return Err(no_observations(
            "no worker-period observations were supplied",
        ));
    }

    let mut sorted = Vec::with_capacity(observations.len());
    for observation in observations {
        let worker = FirmKey::new(observation.worker, "worker")?;
        if !observation.time.is_finite() {
            return Err(invalid_data("panel time values must be finite"));
        }
        let firm = observation
            .firm
            .map(|value| FirmKey::new(value, "panel"))
            .transpose()?;
        sorted.push(ValidatedObservation {
            worker,
            firm,
            time: if observation.time == 0.0 {
                0.0
            } else {
                observation.time
            },
        });
    }
    sorted.sort_by(|left, right| {
        left.worker
            .cmp(&right.worker)
            .then_with(|| left.time.total_cmp(&right.time))
            .then_with(|| left.firm.cmp(&right.firm))
    });

    let mut accounting = GraphAccounting {
        input_rows: observations.len(),
        ..GraphAccounting::default()
    };
    let mut moves = Vec::new();
    let mut previous_worker = None;
    let mut previous_valid: Option<(f64, FirmKey)> = None;
    for observation in sorted {
        if previous_worker != Some(observation.worker) {
            accounting.workers += 1;
            previous_worker = Some(observation.worker);
            previous_valid = None;
        } else if let Some((previous_time, _)) = previous_valid {
            if observation.time.total_cmp(&previous_time) == Ordering::Equal {
                return Err(invalid_data(format!(
                    "duplicate worker-time observation for worker {} at time {}",
                    observation.worker.0, observation.time
                )));
            }
        }

        let Some(current_firm) = observation.firm else {
            accounting.missing_firm_breaks += 1;
            previous_valid = None;
            continue;
        };
        if let Some((previous_time, previous_firm)) = previous_valid {
            let gap = observation.time - previous_time;
            if gap <= 0.0 {
                return Err(invalid_data("panel time must increase within worker"));
            }
            if gap > max_gap {
                accounting.gap_breaks += 1;
            } else if current_firm == previous_firm {
                accounting.same_firm_continuations += 1;
            } else {
                accounting.valid_moves += 1;
                moves.push(EdgeInput {
                    origin: previous_firm.0,
                    destination: current_firm.0,
                    flow: 1.0,
                });
            }
        }
        previous_valid = Some((observation.time, current_firm));
    }

    if moves.is_empty() {
        return Err(no_observations(
            "the panel contract constructed no valid worker moves",
        ));
    }
    let mut graph = canonicalize_edges(&moves, options)?;
    accounting.informative_rows = accounting.valid_moves;
    accounting.below_min_flow_edges = graph.accounting.below_min_flow_edges;
    graph.accounting = accounting;
    Ok(graph)
}

/// Produce induced canonical subgraphs for the requested qualifying components.
///
/// # Errors
///
/// Returns an error if the request does not identify an estimable strongly
/// connected component.
pub fn selected_subgraphs(
    graph: &CanonicalGraph,
    selection: ComponentSelection,
) -> Result<Vec<(usize, CanonicalGraph)>> {
    let qualifying: Vec<usize> = graph
        .components
        .iter()
        .filter(|component| component.firms >= 2 && component.edges > 0 && component.flow > 0.0)
        .map(|component| component.id)
        .collect();
    if qualifying.is_empty() {
        return Err(no_observations(
            "the directed graph contains no estimable strongly connected component",
        ));
    }
    let requested = match selection {
        ComponentSelection::Largest => vec![qualifying[0]],
        ComponentSelection::Number(number) => {
            if !qualifying.contains(&number) {
                return Err(invalid(format!(
                    "component {number} is absent or not estimable"
                )));
            }
            vec![number]
        }
        ComponentSelection::All => qualifying,
    };
    requested
        .into_iter()
        .map(|component_id| {
            induced_component(graph, component_id).map(|subgraph| (component_id, subgraph))
        })
        .collect()
}

fn validate_graph_options(options: GraphOptions) -> Result<()> {
    if !options.min_flow.is_finite() || options.min_flow < 0.0 {
        return Err(invalid("min_flow must be nonnegative and finite"));
    }
    Ok(())
}

fn neumaier_add(sum: &mut f64, compensation: &mut f64, value: f64) {
    let updated = *sum + value;
    if sum.abs() >= value.abs() {
        *compensation += (*sum - updated) + value;
    } else {
        *compensation += (value - updated) + *sum;
    }
    *sum = updated;
}

fn build_graph(
    firm_ids: Vec<f64>,
    edges: Vec<Edge>,
    accounting: GraphAccounting,
) -> Result<CanonicalGraph> {
    let firms = firm_ids.len();
    if firms == 0 || edges.is_empty() {
        return Err(no_observations("canonical graph is empty"));
    }
    let mut inflow = vec![0.0; firms];
    let mut inflow_compensation = vec![0.0; firms];
    let mut outflow = vec![0.0; firms];
    let mut outflow_compensation = vec![0.0; firms];
    let mut in_degree = vec![0; firms];
    let mut out_degree = vec![0; firms];
    let mut outgoing = vec![Vec::new(); firms];
    let mut incoming = vec![Vec::new(); firms];
    for edge in &edges {
        if edge.origin >= firms || edge.destination >= firms || edge.origin == edge.destination {
            return Err(invalid_data("canonical edge index is invalid"));
        }
        neumaier_add(
            &mut outflow[edge.origin],
            &mut outflow_compensation[edge.origin],
            edge.flow,
        );
        neumaier_add(
            &mut inflow[edge.destination],
            &mut inflow_compensation[edge.destination],
            edge.flow,
        );
        out_degree[edge.origin] += 1;
        in_degree[edge.destination] += 1;
        outgoing[edge.origin].push(edge.destination);
        incoming[edge.destination].push(edge.origin);
    }
    for (value, correction) in inflow.iter_mut().zip(inflow_compensation) {
        *value += correction;
    }
    for (value, correction) in outflow.iter_mut().zip(outflow_compensation) {
        *value += correction;
    }
    for neighbors in outgoing.iter_mut().chain(incoming.iter_mut()) {
        neighbors.sort_unstable();
        neighbors.dedup();
    }
    let raw_assignment = kosaraju(&outgoing, &incoming);
    let raw_count = raw_assignment.iter().max().map_or(0, |value| value + 1);
    let mut raw_firms = vec![Vec::new(); raw_count];
    for (firm, &component) in raw_assignment.iter().enumerate() {
        raw_firms[component].push(firm);
    }
    let mut raw_edges = vec![0_usize; raw_count];
    let mut raw_flows = vec![0.0; raw_count];
    for edge in &edges {
        let component = raw_assignment[edge.origin];
        if component == raw_assignment[edge.destination] {
            raw_edges[component] += 1;
            raw_flows[component] += edge.flow;
        }
    }
    let mut order: Vec<usize> = (0..raw_count).collect();
    order.sort_by(|&left, &right| {
        raw_firms[right]
            .len()
            .cmp(&raw_firms[left].len())
            .then_with(|| raw_flows[right].total_cmp(&raw_flows[left]))
            .then_with(|| firm_ids[raw_firms[left][0]].total_cmp(&firm_ids[raw_firms[right][0]]))
    });
    let mut reported_for_raw = vec![0_usize; raw_count];
    let mut components = Vec::with_capacity(raw_count);
    for (position, &raw) in order.iter().enumerate() {
        let id = position + 1;
        reported_for_raw[raw] = id;
        components.push(ComponentSummary {
            id,
            firms: raw_firms[raw].len(),
            edges: raw_edges[raw],
            flow: raw_flows[raw],
            minimum_firm_id: firm_ids[raw_firms[raw][0]],
        });
    }
    let component_id = raw_assignment
        .iter()
        .map(|&raw| reported_for_raw[raw])
        .collect();
    Ok(CanonicalGraph {
        firm_ids,
        edges,
        inflow,
        outflow,
        in_degree,
        out_degree,
        component_id,
        components,
        accounting,
    })
}

fn kosaraju(outgoing: &[Vec<usize>], incoming: &[Vec<usize>]) -> Vec<usize> {
    let firms = outgoing.len();
    let mut visited = vec![false; firms];
    let mut finishing = Vec::with_capacity(firms);
    for root in 0..firms {
        if visited[root] {
            continue;
        }
        visited[root] = true;
        let mut stack = vec![(root, 0_usize)];
        while let Some((node, next_neighbor)) = stack.last_mut() {
            if *next_neighbor < outgoing[*node].len() {
                let neighbor = outgoing[*node][*next_neighbor];
                *next_neighbor += 1;
                if !visited[neighbor] {
                    visited[neighbor] = true;
                    stack.push((neighbor, 0));
                }
            } else {
                finishing.push(*node);
                stack.pop();
            }
        }
    }

    let mut assignment = vec![usize::MAX; firms];
    let mut component = 0;
    for &root in finishing.iter().rev() {
        if assignment[root] != usize::MAX {
            continue;
        }
        assignment[root] = component;
        let mut stack = vec![root];
        while let Some(node) = stack.pop() {
            for &neighbor in incoming[node].iter().rev() {
                if assignment[neighbor] == usize::MAX {
                    assignment[neighbor] = component;
                    stack.push(neighbor);
                }
            }
        }
        component += 1;
    }
    assignment
}

fn induced_component(graph: &CanonicalGraph, component_id: usize) -> Result<CanonicalGraph> {
    let retained: Vec<usize> = graph
        .component_id
        .iter()
        .enumerate()
        .filter_map(|(firm, &component)| (component == component_id).then_some(firm))
        .collect();
    let mut old_to_new = vec![usize::MAX; graph.firm_ids.len()];
    for (new, &old) in retained.iter().enumerate() {
        old_to_new[old] = new;
    }
    let firm_ids = retained.iter().map(|&old| graph.firm_ids[old]).collect();
    let edges: Vec<Edge> = graph
        .edges
        .iter()
        .filter(|edge| {
            graph.component_id[edge.origin] == component_id
                && graph.component_id[edge.destination] == component_id
        })
        .map(|edge| Edge {
            origin: old_to_new[edge.origin],
            destination: old_to_new[edge.destination],
            flow: edge.flow,
        })
        .collect();
    let mut subgraph = build_graph(firm_ids, edges, graph.accounting.clone())?;
    subgraph.component_id.fill(component_id);
    if let Some(summary) = subgraph.components.first_mut() {
        summary.id = component_id;
    }
    Ok(subgraph)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn edge(origin: f64, destination: f64, flow: f64) -> EdgeInput {
        EdgeInput {
            origin,
            destination,
            flow,
        }
    }

    #[test]
    fn aggregation_is_permutation_and_split_invariant() {
        let first = canonicalize_edges(
            &[
                edge(1.0, 2.0, 0.25),
                edge(2.0, 1.0, 2.0),
                edge(1.0, 2.0, 0.75),
            ],
            GraphOptions::default(),
        )
        .unwrap();
        let second = canonicalize_edges(
            &[edge(1.0, 2.0, 1.0), edge(2.0, 1.0, 2.0)],
            GraphOptions::default(),
        )
        .unwrap();
        assert_eq!(first.firm_ids, second.firm_ids);
        assert_eq!(first.edges, second.edges);
    }

    #[test]
    fn components_use_pinned_tie_breaks() {
        let graph = canonicalize_edges(
            &[
                edge(1.0, 2.0, 1.0),
                edge(2.0, 1.0, 1.0),
                edge(10.0, 11.0, 2.0),
                edge(11.0, 10.0, 2.0),
            ],
            GraphOptions::default(),
        )
        .unwrap();
        assert_eq!(graph.components[0].minimum_firm_id, 10.0);
        assert_eq!(graph.components[1].minimum_firm_id, 1.0);
    }

    #[test]
    fn panel_contract_observes_gaps_and_missing_breaks() {
        let rows = [
            PanelObservation {
                worker: 1.0,
                firm: Some(10.0),
                time: 1.0,
            },
            PanelObservation {
                worker: 1.0,
                firm: Some(20.0),
                time: 2.0,
            },
            PanelObservation {
                worker: 1.0,
                firm: None,
                time: 3.0,
            },
            PanelObservation {
                worker: 1.0,
                firm: Some(10.0),
                time: 4.0,
            },
            PanelObservation {
                worker: 2.0,
                firm: Some(20.0),
                time: 1.0,
            },
            PanelObservation {
                worker: 2.0,
                firm: Some(10.0),
                time: 2.0,
            },
        ];
        let graph = canonicalize_panel(&rows, 1.0, GraphOptions::default()).unwrap();
        assert_eq!(graph.accounting.valid_moves, 2);
        assert_eq!(graph.accounting.missing_firm_breaks, 1);
        assert_eq!(graph.accounting.workers, 2);
        assert_eq!(graph.components[0].firms, 2);
    }

    #[test]
    fn duplicate_worker_time_is_an_error() {
        let rows = [
            PanelObservation {
                worker: 1.0,
                firm: Some(10.0),
                time: 1.0,
            },
            PanelObservation {
                worker: 1.0,
                firm: Some(20.0),
                time: 1.0,
            },
        ];
        assert!(canonicalize_panel(&rows, 1.0, GraphOptions::default()).is_err());
    }
}
