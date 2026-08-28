//! Deterministic multilevel graph preconditioner for zero-sum Laplacian solves.
//!
//! The narrow adapter is a `ferank`-specific adaptation of the pinned CMG
//! hierarchy identified in `vendor/cmg/PROVENANCE.md`. It accepts an ordinary
//! connected weighted graph rather than the source project's worker/firm
//! hybrid graph.

use std::collections::BTreeMap;

use crate::error::{no_convergence, Result};
use crate::rank::compensated_sum;

const TERMINAL_VERTICES: usize = 32;
const MAXIMUM_LEVELS: usize = 64;
const JACOBI_WEIGHT: f64 = 2.0 / 3.0;

#[derive(Debug, Clone, Copy)]
pub(crate) struct WeightedEdge {
    pub(crate) left: usize,
    pub(crate) right: usize,
    pub(crate) weight: f64,
}

#[derive(Debug)]
struct Level {
    vertices: usize,
    edges: Vec<WeightedEdge>,
    diagonal: Vec<f64>,
    aggregate: Option<Vec<usize>>,
    coarse_vertices: usize,
}

/// Compact hierarchy diagnostics retained by the Bradley--Terry solver.
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct CmgReceipt {
    pub(crate) levels: usize,
    pub(crate) terminal_vertices: usize,
    pub(crate) edge_complexity: f64,
}

/// Deterministic symmetric V-cycle preconditioner.
#[derive(Debug)]
pub(crate) struct CmgPreconditioner {
    levels: Vec<Level>,
    receipt: CmgReceipt,
}

impl CmgPreconditioner {
    pub(crate) fn build(vertices: usize, mut edges: Vec<WeightedEdge>) -> Result<Self> {
        if vertices < 2 || edges.is_empty() {
            return Err(no_convergence("CMG requires a nontrivial connected graph"));
        }
        canonicalize_edges(vertices, &mut edges)?;
        let fine_edges = edges.len();
        let mut levels = Vec::new();
        let mut current_vertices = vertices;
        let mut current_edges = edges;
        loop {
            let diagonal = graph_diagonal(current_vertices, &current_edges)?;
            if current_vertices <= TERMINAL_VERTICES || levels.len() + 1 >= MAXIMUM_LEVELS {
                levels.push(Level {
                    vertices: current_vertices,
                    edges: current_edges,
                    diagonal,
                    aggregate: None,
                    coarse_vertices: 0,
                });
                break;
            }
            let (aggregate, coarse_vertices) =
                heavy_edge_aggregates(current_vertices, &current_edges, &diagonal);
            if coarse_vertices >= current_vertices {
                levels.push(Level {
                    vertices: current_vertices,
                    edges: current_edges,
                    diagonal,
                    aggregate: None,
                    coarse_vertices: 0,
                });
                break;
            }
            let coarse_edges = coarsen(&current_edges, &aggregate, coarse_vertices)?;
            levels.push(Level {
                vertices: current_vertices,
                edges: current_edges,
                diagonal,
                aggregate: Some(aggregate),
                coarse_vertices,
            });
            current_vertices = coarse_vertices;
            current_edges = coarse_edges;
        }
        let total_edges: usize = levels.iter().map(|level| level.edges.len()).sum();
        let terminal_vertices = levels.last().map_or(0, |level| level.vertices);
        let level_count = levels.len();
        Ok(Self {
            levels,
            receipt: CmgReceipt {
                levels: level_count,
                terminal_vertices,
                edge_complexity: total_edges as f64 / fine_edges as f64,
            },
        })
    }

    pub(crate) fn apply(&self, rhs: &[f64]) -> Result<Vec<f64>> {
        if rhs.len() != self.levels[0].vertices {
            return Err(no_convergence(
                "CMG right-hand side has the wrong dimension",
            ));
        }
        let mut centered = rhs.to_vec();
        center(&mut centered);
        let mut solution = self.v_cycle(0, &centered)?;
        center(&mut solution);
        if solution.iter().any(|value| !value.is_finite()) {
            return Err(no_convergence(
                "CMG produced a nonfinite preconditioned vector",
            ));
        }
        Ok(solution)
    }

    pub(crate) const fn receipt(&self) -> CmgReceipt {
        self.receipt
    }

    fn v_cycle(&self, level_index: usize, rhs: &[f64]) -> Result<Vec<f64>> {
        let level = &self.levels[level_index];
        if level.aggregate.is_none() {
            return terminal_solve(level, rhs);
        }
        let mut solution = vec![0.0; level.vertices];
        jacobi(level, rhs, &mut solution);
        let action = laplacian_product(level, &solution);
        let residual: Vec<f64> = rhs
            .iter()
            .zip(action)
            .map(|(left, right)| left - right)
            .collect();
        let aggregate = level.aggregate.as_ref().expect("checked aggregate");
        let mut coarse_rhs = vec![0.0; level.coarse_vertices];
        for (vertex, &coarse) in aggregate.iter().enumerate() {
            coarse_rhs[coarse] += residual[vertex];
        }
        center(&mut coarse_rhs);
        let coarse_correction = self.v_cycle(level_index + 1, &coarse_rhs)?;
        for (vertex, &coarse) in aggregate.iter().enumerate() {
            solution[vertex] += coarse_correction[coarse];
        }
        jacobi(level, rhs, &mut solution);
        center(&mut solution);
        Ok(solution)
    }
}

fn canonicalize_edges(vertices: usize, edges: &mut Vec<WeightedEdge>) -> Result<()> {
    for edge in edges.iter_mut() {
        if edge.left > edge.right {
            std::mem::swap(&mut edge.left, &mut edge.right);
        }
        if edge.left == edge.right
            || edge.right >= vertices
            || !edge.weight.is_finite()
            || edge.weight <= 0.0
        {
            return Err(no_convergence("CMG received an invalid weighted edge"));
        }
    }
    edges.sort_by(|left, right| {
        left.left
            .cmp(&right.left)
            .then_with(|| left.right.cmp(&right.right))
            .then_with(|| left.weight.total_cmp(&right.weight))
    });
    let mut collapsed: Vec<WeightedEdge> = Vec::with_capacity(edges.len());
    for edge in edges.iter() {
        if let Some(previous) = collapsed.last_mut() {
            if previous.left == edge.left && previous.right == edge.right {
                previous.weight += edge.weight;
                continue;
            }
        }
        collapsed.push(*edge);
    }
    *edges = collapsed;
    Ok(())
}

fn graph_diagonal(vertices: usize, edges: &[WeightedEdge]) -> Result<Vec<f64>> {
    let mut diagonal = vec![0.0; vertices];
    for edge in edges {
        diagonal[edge.left] += edge.weight;
        diagonal[edge.right] += edge.weight;
    }
    if diagonal
        .iter()
        .any(|value| !value.is_finite() || *value <= 0.0)
    {
        return Err(no_convergence(
            "CMG graph is disconnected or has invalid degree",
        ));
    }
    Ok(diagonal)
}

fn heavy_edge_aggregates(
    vertices: usize,
    edges: &[WeightedEdge],
    diagonal: &[f64],
) -> (Vec<usize>, usize) {
    let mut neighbors = vec![Vec::<(usize, f64)>::new(); vertices];
    for edge in edges {
        neighbors[edge.left].push((edge.right, edge.weight));
        neighbors[edge.right].push((edge.left, edge.weight));
    }
    for values in &mut neighbors {
        values.sort_by_key(|&(neighbor, _)| neighbor);
    }
    let mut aggregate = vec![usize::MAX; vertices];
    let mut count = 0;
    for vertex in 0..vertices {
        if aggregate[vertex] != usize::MAX {
            continue;
        }
        let partner = neighbors[vertex]
            .iter()
            .filter(|(neighbor, _)| aggregate[*neighbor] == usize::MAX)
            .max_by(
                |(left_neighbor, left_weight), (right_neighbor, right_weight)| {
                    let left_score =
                        *left_weight / (diagonal[vertex] * diagonal[*left_neighbor]).sqrt();
                    let right_score =
                        *right_weight / (diagonal[vertex] * diagonal[*right_neighbor]).sqrt();
                    left_score
                        .total_cmp(&right_score)
                        .then_with(|| right_neighbor.cmp(left_neighbor))
                },
            )
            .map(|(neighbor, _)| *neighbor);
        aggregate[vertex] = count;
        if let Some(partner) = partner {
            aggregate[partner] = count;
        }
        count += 1;
    }
    (aggregate, count)
}

fn coarsen(
    edges: &[WeightedEdge],
    aggregate: &[usize],
    coarse_vertices: usize,
) -> Result<Vec<WeightedEdge>> {
    let mut weights: BTreeMap<(usize, usize), f64> = BTreeMap::new();
    for edge in edges {
        let mut left = aggregate[edge.left];
        let mut right = aggregate[edge.right];
        if left == right {
            continue;
        }
        if left > right {
            std::mem::swap(&mut left, &mut right);
        }
        *weights.entry((left, right)).or_default() += edge.weight;
    }
    let mut result: Vec<WeightedEdge> = weights
        .into_iter()
        .map(|((left, right), weight)| WeightedEdge {
            left,
            right,
            weight,
        })
        .collect();
    canonicalize_edges(coarse_vertices, &mut result)?;
    Ok(result)
}

fn jacobi(level: &Level, rhs: &[f64], solution: &mut [f64]) {
    let action = laplacian_product(level, solution);
    for vertex in 0..level.vertices {
        solution[vertex] += JACOBI_WEIGHT * (rhs[vertex] - action[vertex]) / level.diagonal[vertex];
    }
    center(solution);
}

fn laplacian_product(level: &Level, vector: &[f64]) -> Vec<f64> {
    let mut result = vec![0.0; level.vertices];
    for edge in &level.edges {
        let value = edge.weight * (vector[edge.left] - vector[edge.right]);
        result[edge.left] += value;
        result[edge.right] -= value;
    }
    result
}

fn terminal_solve(level: &Level, rhs: &[f64]) -> Result<Vec<f64>> {
    let vertices = level.vertices;
    let dimension = vertices + 1;
    let mut matrix = vec![0.0; dimension * dimension];
    for edge in &level.edges {
        matrix[edge.left * dimension + edge.left] += edge.weight;
        matrix[edge.right * dimension + edge.right] += edge.weight;
        matrix[edge.left * dimension + edge.right] -= edge.weight;
        matrix[edge.right * dimension + edge.left] -= edge.weight;
    }
    let mut right_hand_side = vec![0.0; dimension];
    right_hand_side[..vertices].copy_from_slice(rhs);
    for vertex in 0..vertices {
        matrix[vertex * dimension + vertices] = 1.0;
        matrix[vertices * dimension + vertex] = 1.0;
    }
    for column in 0..dimension {
        let pivot = (column..dimension)
            .max_by(|&left, &right| {
                matrix[left * dimension + column]
                    .abs()
                    .total_cmp(&matrix[right * dimension + column].abs())
            })
            .unwrap_or(column);
        if matrix[pivot * dimension + column].abs() <= 1e-15 {
            return Err(no_convergence("CMG terminal system is singular"));
        }
        if pivot != column {
            for index in column..dimension {
                matrix.swap(column * dimension + index, pivot * dimension + index);
            }
            right_hand_side.swap(column, pivot);
        }
        let diagonal = matrix[column * dimension + column];
        for row in (column + 1)..dimension {
            let factor = matrix[row * dimension + column] / diagonal;
            for index in column..dimension {
                matrix[row * dimension + index] -= factor * matrix[column * dimension + index];
            }
            right_hand_side[row] -= factor * right_hand_side[column];
        }
    }
    let mut solution = vec![0.0; dimension];
    for row in (0..dimension).rev() {
        let trailing = ((row + 1)..dimension)
            .map(|column| matrix[row * dimension + column] * solution[column])
            .sum::<f64>();
        solution[row] = (right_hand_side[row] - trailing) / matrix[row * dimension + row];
    }
    solution.truncate(vertices);
    center(&mut solution);
    Ok(solution)
}

fn center(values: &mut [f64]) {
    let mean = compensated_sum(values) / values.len() as f64;
    for value in values {
        *value -= mean;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn v_cycle_reduces_a_path_residual() {
        let vertices = 128;
        let edges: Vec<WeightedEdge> = (0..(vertices - 1))
            .map(|left| WeightedEdge {
                left,
                right: left + 1,
                weight: 1.0,
            })
            .collect();
        let cmg = CmgPreconditioner::build(vertices, edges.clone()).unwrap();
        let mut rhs = vec![0.0; vertices];
        rhs[0] = 1.0;
        rhs[vertices - 1] = -1.0;
        let solution = cmg.apply(&rhs).unwrap();
        let level = Level {
            vertices,
            diagonal: graph_diagonal(vertices, &edges).unwrap(),
            edges,
            aggregate: None,
            coarse_vertices: 0,
        };
        let action = laplacian_product(&level, &solution);
        let residual = action
            .iter()
            .zip(rhs)
            .map(|(left, right)| (left - right).abs())
            .fold(0.0_f64, f64::max);
        assert!(residual < 1.0);
        assert!(cmg.receipt().levels > 1);
    }
}
