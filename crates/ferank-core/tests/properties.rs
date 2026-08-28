//! Cross-module invariance, edge-case, and routed-solver properties.

use ferank_core::{
    canonicalize_edges, canonicalize_panel, estimate_bradley_terry, estimate_reference,
    estimate_sorkin, BradleyTerryOptions, ComponentSelection, EdgeInput, GraphOptions, Method,
    Normalization, PanelObservation, SolverOptions, SorkinOptions,
};

fn edge(origin: f64, destination: f64, flow: f64) -> EdgeInput {
    EdgeInput {
        origin,
        destination,
        flow,
    }
}

fn asymmetric_fixture() -> Vec<EdgeInput> {
    vec![
        edge(1.0, 2.0, 4.0),
        edge(2.0, 1.0, 1.0),
        edge(2.0, 3.0, 3.0),
        edge(3.0, 2.0, 1.0),
        edge(3.0, 1.0, 2.0),
        edge(1.0, 3.0, 1.0),
    ]
}

#[test]
fn both_methods_are_invariant_to_input_permutation() {
    let rows = asymmetric_fixture();
    let mut reversed = rows.clone();
    reversed.reverse();
    let first = canonicalize_edges(&rows, GraphOptions::default()).unwrap();
    let second = canonicalize_edges(&reversed, GraphOptions::default()).unwrap();
    assert_eq!(first.edges, second.edges);
    let first_sorkin = estimate_sorkin(
        &first,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions::default(),
    )
    .unwrap();
    let second_sorkin = estimate_sorkin(
        &second,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions::default(),
    )
    .unwrap();
    assert_eq!(first_sorkin.firms, second_sorkin.firms);
    let first_bt = estimate_bradley_terry(
        &first,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions::default(),
    )
    .unwrap();
    let second_bt = estimate_bradley_terry(
        &second,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions::default(),
    )
    .unwrap();
    assert_eq!(first_bt.firms, second_bt.firms);
}

#[test]
fn duplicate_splitting_and_relabeling_preserve_scores() {
    let original = canonicalize_edges(&asymmetric_fixture(), GraphOptions::default()).unwrap();
    let mut transformed = Vec::new();
    for row in asymmetric_fixture() {
        transformed.push(edge(
            row.origin + 100.0,
            row.destination + 100.0,
            row.flow / 4.0,
        ));
        transformed.push(edge(
            row.origin + 100.0,
            row.destination + 100.0,
            3.0 * row.flow / 4.0,
        ));
    }
    let transformed = canonicalize_edges(&transformed, GraphOptions::default()).unwrap();
    let original = estimate_sorkin(
        &original,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions::default(),
    )
    .unwrap();
    let transformed = estimate_sorkin(
        &transformed,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions::default(),
    )
    .unwrap();
    for (left, right) in original.firms.iter().zip(transformed.firms) {
        assert!((left.score - right.score).abs() < 1e-12);
    }

    let original_graph =
        canonicalize_edges(&asymmetric_fixture(), GraphOptions::default()).unwrap();
    let mut transformed_rows = Vec::new();
    for row in asymmetric_fixture() {
        transformed_rows.push(edge(
            row.origin + 100.0,
            row.destination + 100.0,
            row.flow / 4.0,
        ));
        transformed_rows.push(edge(
            row.origin + 100.0,
            row.destination + 100.0,
            3.0 * row.flow / 4.0,
        ));
    }
    let transformed_graph = canonicalize_edges(&transformed_rows, GraphOptions::default()).unwrap();
    let original_bt = estimate_bradley_terry(
        &original_graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions::default(),
    )
    .unwrap();
    let transformed_bt = estimate_bradley_terry(
        &transformed_graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions::default(),
    )
    .unwrap();
    for (left, right) in original_bt.firms.iter().zip(transformed_bt.firms) {
        assert!((left.score - right.score).abs() < 1e-12);
    }
}

#[test]
fn filtering_and_component_accounting_are_explicit() {
    let graph = canonicalize_edges(
        &[
            edge(1.0, 1.0, 10.0),
            edge(1.0, 2.0, 0.0),
            edge(1.0, 2.0, 0.4),
            edge(2.0, 1.0, 0.5),
            edge(3.0, 4.0, 2.0),
            edge(4.0, 3.0, 2.0),
        ],
        GraphOptions { min_flow: 0.5 },
    )
    .unwrap();
    assert_eq!(graph.accounting.self_move_rows, 1);
    assert_eq!(graph.accounting.zero_flow_rows, 1);
    assert_eq!(graph.accounting.below_min_flow_edges, 1);
    assert_eq!(graph.components[0].minimum_firm_id, 3.0);
}

#[test]
fn panel_gap_same_firm_and_missing_rules_are_pinned() {
    let rows = [
        PanelObservation {
            worker: 1.0,
            firm: Some(1.0),
            time: 1.0,
        },
        PanelObservation {
            worker: 1.0,
            firm: Some(1.0),
            time: 2.0,
        },
        PanelObservation {
            worker: 1.0,
            firm: Some(2.0),
            time: 4.0,
        },
        PanelObservation {
            worker: 1.0,
            firm: None,
            time: 5.0,
        },
        PanelObservation {
            worker: 1.0,
            firm: Some(2.0),
            time: 6.0,
        },
        PanelObservation {
            worker: 2.0,
            firm: Some(2.0),
            time: 1.0,
        },
        PanelObservation {
            worker: 2.0,
            firm: Some(1.0),
            time: 2.0,
        },
        PanelObservation {
            worker: 3.0,
            firm: Some(1.0),
            time: 1.0,
        },
        PanelObservation {
            worker: 3.0,
            firm: Some(2.0),
            time: 2.0,
        },
    ];
    let graph = canonicalize_panel(&rows, 1.0, GraphOptions::default()).unwrap();
    let mut reversed = rows;
    reversed.reverse();
    let permuted = canonicalize_panel(&reversed, 1.0, GraphOptions::default()).unwrap();
    assert_eq!(graph, permuted);
    assert_eq!(graph.accounting.same_firm_continuations, 1);
    assert_eq!(graph.accounting.gap_breaks, 1);
    assert_eq!(graph.accounting.missing_firm_breaks, 1);
    assert_eq!(graph.accounting.valid_moves, 2);
}

#[test]
fn invalid_and_extreme_flows_are_handled_explicitly() {
    for flow in [-1.0, f64::NAN, f64::INFINITY] {
        assert!(canonicalize_edges(&[edge(1.0, 2.0, flow)], GraphOptions::default()).is_err());
    }
    let graph = canonicalize_edges(
        &[edge(1.0, 2.0, 1e300), edge(2.0, 1.0, 1e300)],
        GraphOptions::default(),
    )
    .unwrap();
    assert!(graph.inflow.iter().all(|value| value.is_finite()));
}

#[test]
fn nearly_reducible_sorkin_graph_retains_original_equation_certificate() {
    let graph = canonicalize_edges(
        &[
            edge(1.0, 2.0, 1.0),
            edge(2.0, 1.0, 1.0),
            edge(3.0, 4.0, 1.0),
            edge(4.0, 3.0, 1.0),
            edge(2.0, 3.0, 0.001),
            edge(3.0, 2.0, 0.001),
        ],
        GraphOptions::default(),
    )
    .unwrap();
    assert!(estimate_sorkin(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions::default(),
    )
    .is_err());
    let result = estimate_sorkin(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions {
            solver: SolverOptions {
                max_iterations: 100_000,
                ..SolverOptions::default()
            },
            ..SorkinOptions::default()
        },
    )
    .unwrap();
    match result.diagnostics.first().unwrap() {
        ferank_core::Diagnostics::Sorkin {
            residual_max,
            residual_l1,
            ..
        } => {
            assert!(*residual_max <= 1e-10);
            assert!(*residual_l1 <= 1e-10);
        }
        ferank_core::Diagnostics::BradleyTerry { .. } => panic!("wrong diagnostics"),
    }
}

#[test]
fn periodic_sorkin_cycle_converges_under_laziness() {
    let graph = canonicalize_edges(
        &[
            edge(1.0, 2.0, 1.0),
            edge(2.0, 3.0, 1.0),
            edge(3.0, 1.0, 1.0),
        ],
        GraphOptions::default(),
    )
    .unwrap();
    let result = estimate_sorkin(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions::default(),
    )
    .unwrap();
    assert!(result.firms.iter().all(|row| row.score.abs() < 1e-12));
}

#[test]
fn one_thread_and_requested_multi_thread_results_agree() {
    let graph = canonicalize_edges(&asymmetric_fixture(), GraphOptions::default()).unwrap();
    let one = estimate_sorkin(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions {
            solver: SolverOptions {
                threads: 1,
                ..SolverOptions::default()
            },
            ..SorkinOptions::default()
        },
    )
    .unwrap();
    let four = estimate_sorkin(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions {
            solver: SolverOptions {
                threads: 4,
                ..SolverOptions::default()
            },
            ..SorkinOptions::default()
        },
    )
    .unwrap();
    assert_eq!(one.firms, four.firms);

    let one_bt = estimate_bradley_terry(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions {
            solver: SolverOptions {
                threads: 1,
                ..SolverOptions::default()
            },
            ..BradleyTerryOptions::default()
        },
    )
    .unwrap();
    let four_bt = estimate_bradley_terry(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions {
            solver: SolverOptions {
                threads: 4,
                ..SolverOptions::default()
            },
            ..BradleyTerryOptions::default()
        },
    )
    .unwrap();
    assert_eq!(one_bt.firms, four_bt.firms);
}

#[test]
fn cmg_pcg_route_is_certified_on_a_nontrivial_graph() {
    let firms = 40;
    let mut rows = Vec::new();
    for firm in 0..firms {
        let next = (firm + 1) % firms;
        rows.push(edge(f64::from(firm), f64::from(next), 2.0));
        rows.push(edge(f64::from(next), f64::from(firm), 1.0));
    }
    rows.push(edge(0.0, 20.0, 1.0));
    rows.push(edge(20.0, 0.0, 0.5));
    let graph = canonicalize_edges(&rows, GraphOptions::default()).unwrap();
    let result = estimate_bradley_terry(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions {
            dense_limit: 16,
            ..BradleyTerryOptions::default()
        },
    )
    .unwrap();
    match &result.diagnostics[0] {
        ferank_core::Diagnostics::BradleyTerry {
            gradient_max,
            linear_route,
            ..
        } => {
            assert!(*gradient_max <= 1e-10);
            assert!(linear_route.starts_with("pcg-cmg("));
        }
        ferank_core::Diagnostics::Sorkin { .. } => panic!("wrong diagnostics"),
    }
    let reference = estimate_reference(
        &graph,
        Method::BradleyTerry,
        ComponentSelection::Largest,
        &Normalization::Mean,
        1e-10,
        20_000,
    )
    .unwrap();
    for (production, oracle) in result.firms.iter().zip(reference.firms) {
        assert!((production.score - oracle.score).abs() < 1e-8);
    }
}

#[test]
fn disconnected_one_way_graph_is_rejected() {
    let graph = canonicalize_edges(&[edge(1.0, 2.0, 1.0)], GraphOptions::default()).unwrap();
    assert!(estimate_bradley_terry(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions::default(),
    )
    .is_err());
}
