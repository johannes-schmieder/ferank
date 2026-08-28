//! Stable errors returned by the numerical core.

use std::error::Error;
use std::fmt::{Display, Formatter};

/// Machine-stable error classes used by the Stata boundary.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum ErrorCode {
    /// Invalid syntax or option value.
    InvalidArgument = 198,
    /// Invalid or unsupported data.
    InvalidData = 459,
    /// No usable observations or graph component.
    NoObservations = 2000,
    /// A numerical iteration did not meet its certificate.
    NoConvergence = 430,
    /// Allocation or representability failure.
    Allocation = 909,
    /// The user interrupted computation.
    Interrupted = 1,
    /// The Stata plugin ABI was unavailable or inconsistent.
    Plugin = 498,
    /// An internal invariant failed.
    Internal = 3498,
}

/// Error value with a stable code and human-readable context.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FerankError {
    code: ErrorCode,
    message: String,
}

impl FerankError {
    /// Construct a new error.
    #[must_use]
    pub fn new(code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }

    /// Return the stable error class.
    #[must_use]
    pub const fn code(&self) -> ErrorCode {
        self.code
    }

    /// Return the explanatory message.
    #[must_use]
    pub fn message(&self) -> &str {
        &self.message
    }
}

impl Display for FerankError {
    fn fmt(&self, formatter: &mut Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl Error for FerankError {}

/// Core result type.
pub type Result<T> = std::result::Result<T, FerankError>;

pub(crate) fn invalid(message: impl Into<String>) -> FerankError {
    FerankError::new(ErrorCode::InvalidArgument, message)
}

pub(crate) fn invalid_data(message: impl Into<String>) -> FerankError {
    FerankError::new(ErrorCode::InvalidData, message)
}

pub(crate) fn no_observations(message: impl Into<String>) -> FerankError {
    FerankError::new(ErrorCode::NoObservations, message)
}

pub(crate) fn no_convergence(message: impl Into<String>) -> FerankError {
    FerankError::new(ErrorCode::NoConvergence, message)
}
