//! Certified firm rankings from directed worker flows.
//!
//! The crate separates deterministic graph construction from the two numerical
//! estimators. Production solvers always return original-equation evidence.

pub mod bradley_terry;
mod cmg;
pub mod error;
pub mod graph;
pub mod model;
pub mod rank;
pub mod reference;
pub mod sorkin;

pub use bradley_terry::estimate_bradley_terry;
pub use error::{ErrorCode, FerankError, Result};
pub use graph::{canonicalize_edges, canonicalize_panel, selected_subgraphs};
pub use model::*;
pub use reference::estimate_reference;
pub use sorkin::estimate_sorkin;
