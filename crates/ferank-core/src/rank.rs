//! Score normalization and deterministic midranks.

use std::cmp::Ordering;

use crate::error::{invalid, invalid_data, Result};
use crate::model::Normalization;

/// Normalize a score vector in place under the requested rule.
///
/// # Errors
///
/// Returns an error for mismatched dimensions, nonfinite scores, invalid
/// weights, or a reference firm outside the selected component.
pub fn normalize_scores(
    scores: &mut [f64],
    firm_ids: &[f64],
    normalization: &Normalization,
) -> Result<()> {
    if scores.is_empty() || scores.len() != firm_ids.len() {
        return Err(invalid(
            "score and firm-ID vectors must have equal positive length",
        ));
    }
    if scores.iter().any(|value| !value.is_finite()) {
        return Err(invalid_data("cannot normalize nonfinite scores"));
    }
    let center = match normalization {
        Normalization::Mean => compensated_sum(scores) / scores.len() as f64,
        Normalization::Weighted(weights) => {
            if weights.len() != scores.len() {
                return Err(invalid(
                    "normalization weights must align with selected firms",
                ));
            }
            let mut numerator_terms = Vec::with_capacity(scores.len());
            let mut denominator_terms = Vec::with_capacity(scores.len());
            for (&score, &weight) in scores.iter().zip(weights) {
                if !weight.is_finite() || weight < 0.0 {
                    return Err(invalid_data(
                        "normalization weights must be nonnegative and finite",
                    ));
                }
                numerator_terms.push(score * weight);
                denominator_terms.push(weight);
            }
            let denominator = compensated_sum(&denominator_terms);
            if denominator <= 0.0 {
                return Err(invalid_data(
                    "normalization weights must have a positive total",
                ));
            }
            compensated_sum(&numerator_terms) / denominator
        }
        Normalization::Reference(reference) => {
            if !reference.is_finite() {
                return Err(invalid("reference firm identifier must be finite"));
            }
            let reference = if *reference == 0.0 { 0.0 } else { *reference };
            let index = firm_ids
                .iter()
                .position(|value| value.total_cmp(&reference) == Ordering::Equal)
                .ok_or_else(|| invalid("reference firm is outside the selected component"))?;
            scores[index]
        }
    };
    for score in scores {
        *score -= center;
        if *score == 0.0 {
            *score = 0.0;
        }
    }
    Ok(())
}

/// Compute deterministic descending midranks and zero-to-100 percentiles.
#[must_use]
pub fn midranks(scores: &[f64]) -> (Vec<f64>, Vec<f64>) {
    let count = scores.len();
    let mut order: Vec<usize> = (0..count).collect();
    order.sort_by(|&left, &right| {
        scores[right]
            .total_cmp(&scores[left])
            .then_with(|| left.cmp(&right))
    });
    let mut ranks = vec![0.0; count];
    let mut percentiles = vec![0.0; count];
    let mut start = 0;
    while start < count {
        let mut end = start + 1;
        while end < count && scores[order[end]].total_cmp(&scores[order[start]]) == Ordering::Equal
        {
            end += 1;
        }
        let midrank = ((start + 1) as f64 + end as f64) / 2.0;
        let percentile = if count <= 1 {
            100.0
        } else {
            100.0 * (count as f64 - midrank) / (count as f64 - 1.0)
        };
        for &index in &order[start..end] {
            ranks[index] = midrank;
            percentiles[index] = percentile;
        }
        start = end;
    }
    (ranks, percentiles)
}

pub(crate) fn compensated_sum(values: &[f64]) -> f64 {
    let mut sum = 0.0;
    let mut compensation = 0.0;
    for &value in values {
        let updated = sum + value;
        if sum.abs() >= value.abs() {
            compensation += (sum - updated) + value;
        } else {
            compensation += (value - updated) + sum;
        }
        sum = updated;
    }
    sum + compensation
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ties_receive_midrank_without_id_breaking() {
        let (ranks, percentiles) = midranks(&[3.0, 1.0, 3.0, 0.0]);
        assert_eq!(ranks, vec![1.5, 3.0, 1.5, 4.0]);
        assert_eq!(percentiles[0], percentiles[2]);
    }

    #[test]
    fn mean_normalization_is_centered() {
        let mut scores = vec![1.0, 2.0, 6.0];
        normalize_scores(&mut scores, &[1.0, 2.0, 3.0], &Normalization::Mean).unwrap();
        assert!(compensated_sum(&scores).abs() < 1e-14);
    }
}
