//! Narrow Stata SPI dispatcher for `ferank-core`.

use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::time::Instant;

use ferank_core::{
    canonicalize_edges, canonicalize_panel, estimate_bradley_terry, estimate_reference,
    estimate_sorkin, BradleyTerryOptions, ComponentSelection, Diagnostics, EdgeInput, ErrorCode,
    EstimateResult, FerankError, GraphOptions, Method, Normalization, PanelObservation, Result,
    SolverOptions, SorkinOptions,
};

const OUTPUT_FIRM: i32 = 5;
const OUTPUT_SCORE: i32 = 6;
const OUTPUT_RANK: i32 = 7;
const OUTPUT_PERCENTILE: i32 = 8;
const OUTPUT_INFLOW: i32 = 9;
const OUTPUT_OUTFLOW: i32 = 10;
const OUTPUT_IN_DEGREE: i32 = 11;
const OUTPUT_OUT_DEGREE: i32 = 12;
const OUTPUT_Q: i32 = 13;
const OUTPUT_PI: i32 = 14;
const OUTPUT_RESIDUAL: i32 = 15;
const OUTPUT_COMPONENT: i32 = 16;
const INPUT_NORMWEIGHT: i32 = 17;

extern "C" {
    fn ferank_spi_nobs() -> c_int;
    fn ferank_spi_is_missing(value: f64) -> c_int;
    fn ferank_spi_missing_value() -> f64;
    fn ferank_spi_vdata(variable: c_int, observation: c_int, value: *mut f64) -> c_int;
    fn ferank_spi_vstore(variable: c_int, observation: c_int, value: f64) -> c_int;
    fn ferank_spi_scal_save(name: *const c_char, value: f64) -> c_int;
    fn ferank_spi_macro_save(name: *const c_char, value: *const c_char) -> c_int;
    fn ferank_spi_display(message: *const c_char) -> c_int;
    fn ferank_spi_error(message: *const c_char) -> c_int;
    fn ferank_spi_poll() -> c_int;
    fn ferank_spi_stop_requested() -> c_int;
}

/// Return the package version embedded in the native backend.
#[must_use]
pub const fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Run a bounded backend health check without Stata state.
#[must_use]
pub fn selftest() -> bool {
    let rows = [
        EdgeInput {
            origin: 1.0,
            destination: 2.0,
            flow: 1.0,
        },
        EdgeInput {
            origin: 2.0,
            destination: 1.0,
            flow: 1.0,
        },
    ];
    let Ok(graph) = canonicalize_edges(&rows, GraphOptions::default()) else {
        return false;
    };
    estimate_sorkin(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions::default(),
    )
    .is_ok()
        && estimate_bradley_terry(
            &graph,
            ComponentSelection::Largest,
            &Normalization::Mean,
            BradleyTerryOptions::default(),
        )
        .is_ok()
}

/// Stata-facing action dispatcher protected against Rust unwinding.
///
/// # Safety
///
/// `argument_values` must point to `argument_count` valid NUL-terminated strings supplied by the
/// Stata plugin ABI. The official C shim must have initialized the SPI table.
#[no_mangle]
pub unsafe extern "C" fn ferank_dispatch(
    argument_count: c_int,
    argument_values: *const *const c_char,
) -> c_int {
    let outcome = catch_unwind(AssertUnwindSafe(|| {
        let arguments = unsafe { decode_arguments(argument_count, argument_values) }?;
        dispatch(&arguments)
    }));
    match outcome {
        Ok(Ok(())) => 0,
        Ok(Err(error)) => {
            report_error(&error);
            error.code() as c_int
        }
        Err(_) => {
            let error = FerankError::new(
                ErrorCode::Internal,
                "native backend panicked before returning a result",
            );
            report_error(&error);
            ErrorCode::Internal as c_int
        }
    }
}

unsafe fn decode_arguments(
    argument_count: c_int,
    argument_values: *const *const c_char,
) -> Result<Vec<String>> {
    if argument_count < 0 || (argument_count > 0 && argument_values.is_null()) {
        return Err(FerankError::new(
            ErrorCode::InvalidArgument,
            "invalid native argument vector",
        ));
    }
    let length = usize::try_from(argument_count)
        .map_err(|_| FerankError::new(ErrorCode::InvalidArgument, "argument count is too large"))?;
    let raw = unsafe { std::slice::from_raw_parts(argument_values, length) };
    raw.iter()
        .map(|&pointer| {
            if pointer.is_null() {
                return Err(FerankError::new(
                    ErrorCode::InvalidArgument,
                    "native argument is null",
                ));
            }
            unsafe { CStr::from_ptr(pointer) }
                .to_str()
                .map(str::to_owned)
                .map_err(|_| {
                    FerankError::new(
                        ErrorCode::InvalidArgument,
                        "native argument is not valid UTF-8",
                    )
                })
        })
        .collect()
}

fn dispatch(arguments: &[String]) -> Result<()> {
    let Some(action) = arguments.first().map(String::as_str) else {
        return Err(FerankError::new(
            ErrorCode::InvalidArgument,
            "missing native action",
        ));
    };
    match action {
        "version" => display(&format!("ferank.plugin.version={}\n", version())),
        "selftest" => {
            if !selftest() {
                return Err(FerankError::new(
                    ErrorCode::Internal,
                    "bounded native self-test failed",
                ));
            }
            display("FERANK_PLUGIN_SELFTEST_PASS\n")
        }
        "estimate-edge" | "estimate-panel" => {
            let request = Request::parse(action, &arguments[1..])?;
            estimate_and_store(&request)
        }
        _ => Err(FerankError::new(
            ErrorCode::InvalidArgument,
            format!("unknown native action {action:?}"),
        )),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InputMode {
    Edge,
    Panel,
}

#[derive(Debug)]
struct Request {
    mode: InputMode,
    method: Method,
    component: ComponentSelection,
    normalization: String,
    engine: String,
    reference: Option<f64>,
    min_flow: f64,
    max_gap: f64,
    tolerance: f64,
    max_iterations: usize,
    threads: usize,
    lazy: f64,
}

impl Request {
    fn parse(action: &str, arguments: &[String]) -> Result<Self> {
        let mut values = BTreeMap::new();
        for argument in arguments {
            let Some((key, value)) = argument.split_once('=') else {
                return Err(invalid_argument(format!(
                    "native option {argument:?} is not key=value"
                )));
            };
            if values.insert(key.to_owned(), value.to_owned()).is_some() {
                return Err(invalid_argument(format!(
                    "native option {key:?} was repeated"
                )));
            }
        }
        let method = match required(&values, "method")? {
            "sorkin" => Method::Sorkin,
            "bradleyterry" => Method::BradleyTerry,
            value => {
                return Err(invalid_argument(format!(
                    "unknown ranking method {value:?}"
                )))
            }
        };
        let component = match required(&values, "component")? {
            "largest" => ComponentSelection::Largest,
            "all" => ComponentSelection::All,
            value => ComponentSelection::Number(parse(value, "component")?),
        };
        let normalization = required(&values, "normalize")?.to_owned();
        if !matches!(normalization.as_str(), "mean" | "weighted" | "reference") {
            return Err(invalid_argument("unknown normalization rule"));
        }
        let reference = if normalization == "reference" {
            values
                .get("reference")
                .filter(|value| !value.is_empty())
                .map(|value| parse(value, "reference"))
                .transpose()?
        } else {
            None
        };
        if normalization == "reference" && reference.is_none() {
            return Err(invalid_argument(
                "reference normalization requires reference=",
            ));
        }
        let engine = required(&values, "engine")?.to_owned();
        if !matches!(engine.as_str(), "plugin" | "reference") {
            return Err(invalid_argument("unknown numerical engine"));
        }
        Ok(Self {
            mode: if action == "estimate-edge" {
                InputMode::Edge
            } else {
                InputMode::Panel
            },
            method,
            component,
            normalization,
            engine,
            reference,
            min_flow: parse(required(&values, "minflow")?, "minflow")?,
            max_gap: parse(required(&values, "maxgap")?, "maxgap")?,
            tolerance: parse(required(&values, "tolerance")?, "tolerance")?,
            max_iterations: parse(required(&values, "maxiter")?, "maxiter")?,
            threads: parse(required(&values, "threads")?, "threads")?,
            lazy: parse(required(&values, "lazy")?, "lazy")?,
        })
    }
}

fn estimate_and_store(request: &Request) -> Result<()> {
    let total_start = Instant::now();
    let input_graph_start = Instant::now();
    let observations = selected_observations()?;
    let graph = match request.mode {
        InputMode::Edge => {
            let mut rows = Vec::with_capacity(observations.len());
            for &observation in &observations {
                rows.push(EdgeInput {
                    origin: required_numeric(2, observation, "origin firm")?,
                    destination: required_numeric(3, observation, "destination firm")?,
                    flow: required_numeric(4, observation, "flow")?,
                });
            }
            canonicalize_edges(
                &rows,
                GraphOptions {
                    min_flow: request.min_flow,
                },
            )?
        }
        InputMode::Panel => {
            let mut rows = Vec::with_capacity(observations.len());
            for &observation in &observations {
                rows.push(PanelObservation {
                    firm: optional_numeric(2, observation)?,
                    worker: required_numeric(3, observation, "worker")?,
                    time: required_numeric(4, observation, "time")?,
                });
            }
            canonicalize_panel(
                &rows,
                request.max_gap,
                GraphOptions {
                    min_flow: request.min_flow,
                },
            )?
        }
    };
    let input_graph_seconds = input_graph_start.elapsed().as_secs_f64();
    let normalization = normalization(request, &graph.firm_ids, &observations)?;
    let solver = SolverOptions {
        tolerance: request.tolerance,
        max_iterations: request.max_iterations,
        threads: request.threads,
    };
    check_interrupt()?;
    let solve_rank_start = Instant::now();
    let result = if request.engine == "reference" {
        estimate_reference(
            &graph,
            request.method,
            request.component,
            &normalization,
            request.tolerance,
            request.max_iterations,
        )?
    } else {
        match request.method {
            Method::Sorkin => estimate_sorkin(
                &graph,
                request.component,
                &normalization,
                SorkinOptions {
                    solver,
                    lazy: request.lazy,
                },
            )?,
            Method::BradleyTerry => estimate_bradley_terry(
                &graph,
                request.component,
                &normalization,
                BradleyTerryOptions {
                    solver,
                    ..BradleyTerryOptions::default()
                },
            )?,
        }
    };
    let solve_rank_seconds = solve_rank_start.elapsed().as_secs_f64();
    check_interrupt()?;
    let store_start = Instant::now();
    store_result(&result)?;
    let store_seconds = store_start.elapsed().as_secs_f64();
    scalar("__ferank_time_input_graph", input_graph_seconds)?;
    scalar("__ferank_time_solve_rank", solve_rank_seconds)?;
    scalar("__ferank_time_store", store_seconds)?;
    scalar("__ferank_time_total", total_start.elapsed().as_secs_f64())?;
    Ok(())
}

fn selected_observations() -> Result<Vec<i32>> {
    let count = unsafe { ferank_spi_nobs() };
    if count <= 0 {
        return Err(FerankError::new(
            ErrorCode::NoObservations,
            "Stata supplied no observations",
        ));
    }
    let mut observations = Vec::new();
    for observation in 1..=count {
        if observation % 8_192 == 0 {
            check_interrupt()?;
        }
        let touse = required_numeric(1, observation, "sample marker")?;
        if touse != 0.0 {
            observations.push(observation);
        }
    }
    if observations.is_empty() {
        return Err(FerankError::new(
            ErrorCode::NoObservations,
            "the marked sample is empty",
        ));
    }
    Ok(observations)
}

fn normalization(
    request: &Request,
    firm_ids: &[f64],
    observations: &[i32],
) -> Result<Normalization> {
    match request.normalization.as_str() {
        "mean" => Ok(Normalization::Mean),
        "reference" => Ok(Normalization::Reference(
            request.reference.expect("validated"),
        )),
        "weighted" => {
            let mut by_firm = Vec::<(f64, f64)>::new();
            for &observation in observations {
                let firm = match request.mode {
                    InputMode::Edge => required_numeric(2, observation, "origin firm")?,
                    InputMode::Panel => {
                        let Some(value) = optional_numeric(2, observation)? else {
                            continue;
                        };
                        value
                    }
                };
                let weight = required_numeric(INPUT_NORMWEIGHT, observation, "normweight")?;
                if !weight.is_finite() || weight < 0.0 {
                    return Err(FerankError::new(
                        ErrorCode::InvalidData,
                        "normweight values must be nonnegative and finite",
                    ));
                }
                if let Some((_, previous)) = by_firm
                    .iter()
                    .find(|(candidate, _)| candidate.total_cmp(&firm) == Ordering::Equal)
                {
                    if previous.total_cmp(&weight) != Ordering::Equal {
                        return Err(FerankError::new(
                            ErrorCode::InvalidData,
                            "normweight must be constant within firm",
                        ));
                    }
                } else {
                    by_firm.push((firm, weight));
                }
            }
            let weights = firm_ids
                .iter()
                .map(|firm| {
                    by_firm
                        .iter()
                        .find(|(candidate, _)| candidate.total_cmp(firm) == Ordering::Equal)
                        .map(|(_, weight)| *weight)
                        .ok_or_else(|| {
                            FerankError::new(
                                ErrorCode::InvalidData,
                                format!("normweight is missing for firm {firm}"),
                            )
                        })
                })
                .collect::<Result<Vec<_>>>()?;
            Ok(Normalization::Weighted(weights))
        }
        _ => Err(invalid_argument("unknown normalization rule")),
    }
}

#[allow(clippy::too_many_lines)]
fn store_result(result: &EstimateResult) -> Result<()> {
    let missing = unsafe { ferank_spi_missing_value() };
    for (index, row) in result.firms.iter().enumerate() {
        let observation = i32::try_from(index + 1).map_err(|_| {
            FerankError::new(
                ErrorCode::Allocation,
                "result row exceeds Stata integer range",
            )
        })?;
        store(OUTPUT_FIRM, observation, row.firm_id)?;
        store(OUTPUT_SCORE, observation, row.score)?;
        store(OUTPUT_RANK, observation, row.rank)?;
        store(OUTPUT_PERCENTILE, observation, row.percentile)?;
        store(OUTPUT_INFLOW, observation, row.inflow)?;
        store(OUTPUT_OUTFLOW, observation, row.outflow)?;
        store(OUTPUT_IN_DEGREE, observation, row.in_degree as f64)?;
        store(OUTPUT_OUT_DEGREE, observation, row.out_degree as f64)?;
        store(
            OUTPUT_Q,
            observation,
            row.revealed_value_q.unwrap_or(missing),
        )?;
        store(
            OUTPUT_PI,
            observation,
            row.stationary_mass.unwrap_or(missing),
        )?;
        store(
            OUTPUT_RESIDUAL,
            observation,
            row.fixed_point_residual.unwrap_or(missing),
        )?;
        store(OUTPUT_COMPONENT, observation, row.component_id as f64)?;
    }

    scalar("__ferank_n_results", result.firms.len() as f64)?;
    scalar("__ferank_n_firms", result.graph.firm_ids.len() as f64)?;
    scalar("__ferank_n_edges", result.graph.edges.len() as f64)?;
    scalar(
        "__ferank_n_components",
        result.graph.components.len() as f64,
    )?;
    scalar(
        "__ferank_input_rows",
        result.graph.accounting.input_rows as f64,
    )?;
    scalar(
        "__ferank_valid_moves",
        result.graph.accounting.valid_moves as f64,
    )?;
    scalar(
        "__ferank_gap_breaks",
        result.graph.accounting.gap_breaks as f64,
    )?;
    scalar(
        "__ferank_missing_breaks",
        result.graph.accounting.missing_firm_breaks as f64,
    )?;
    scalar(
        "__ferank_same_firm",
        result.graph.accounting.same_firm_continuations as f64,
    )?;

    let mut iterations = 0_usize;
    let mut residual_max = 0.0_f64;
    let mut residual_l1 = 0.0_f64;
    let mut log_likelihood = 0.0_f64;
    let mut gradient_max = 0.0_f64;
    let mut newton_residual = 0.0_f64;
    let mut line_search_steps = 0_usize;
    let mut threads = 1_usize;
    let mut route = String::new();
    for diagnostic in &result.diagnostics {
        match diagnostic {
            Diagnostics::Sorkin {
                iterations: value,
                residual_max: maximum,
                residual_l1: l1,
                threads: value_threads,
                ..
            } => {
                iterations = iterations.max(*value);
                residual_max = residual_max.max(*maximum);
                residual_l1 = residual_l1.max(*l1);
                threads = threads.max(*value_threads);
            }
            Diagnostics::BradleyTerry {
                iterations: value,
                log_likelihood: likelihood,
                line_search_steps: steps,
                gradient_max: gradient,
                newton_residual: newton,
                linear_route,
                threads: value_threads,
                ..
            } => {
                iterations = iterations.max(*value);
                log_likelihood += likelihood;
                line_search_steps += steps;
                gradient_max = gradient_max.max(*gradient);
                newton_residual = newton_residual.max(*newton);
                threads = threads.max(*value_threads);
                route.clone_from(linear_route);
            }
        }
    }
    scalar("__ferank_iterations", iterations as f64)?;
    scalar("__ferank_residual_max", residual_max)?;
    scalar("__ferank_residual_l1", residual_l1)?;
    scalar("__ferank_loglikelihood", log_likelihood)?;
    scalar("__ferank_gradient_max", gradient_max)?;
    scalar("__ferank_newton_residual", newton_residual)?;
    scalar("__ferank_line_search_steps", line_search_steps as f64)?;
    scalar("__ferank_threads", threads as f64)?;
    macro_value(
        "__ferank_method",
        match result.method {
            Method::Sorkin => "sorkin",
            Method::BradleyTerry => "bradleyterry",
        },
    )?;
    macro_value("__ferank_linear_route", &route)?;
    macro_value("__ferank_certificate", "success")?;
    Ok(())
}

fn required_numeric(variable: i32, observation: i32, label: &str) -> Result<f64> {
    optional_numeric(variable, observation)?
        .ok_or_else(|| FerankError::new(ErrorCode::InvalidData, format!("{label} is missing")))
}

fn optional_numeric(variable: i32, observation: i32) -> Result<Option<f64>> {
    let mut value = 0.0;
    let return_code = unsafe { ferank_spi_vdata(variable, observation, &mut value) };
    if return_code != 0 {
        return Err(FerankError::new(
            ErrorCode::Plugin,
            format!("Stata could not read variable {variable} at observation {observation}"),
        ));
    }
    if unsafe { ferank_spi_is_missing(value) } != 0 {
        Ok(None)
    } else {
        Ok(Some(value))
    }
}

fn store(variable: i32, observation: i32, value: f64) -> Result<()> {
    let return_code = unsafe { ferank_spi_vstore(variable, observation, value) };
    if return_code == 0 {
        Ok(())
    } else {
        Err(FerankError::new(
            ErrorCode::Plugin,
            format!("Stata could not store result variable {variable}"),
        ))
    }
}

fn scalar(name: &str, value: f64) -> Result<()> {
    let name = CString::new(name).map_err(|_| invalid_argument("scalar name contains NUL"))?;
    let return_code = unsafe { ferank_spi_scal_save(name.as_ptr(), value) };
    if return_code == 0 {
        Ok(())
    } else {
        Err(FerankError::new(
            ErrorCode::Plugin,
            "Stata could not store a diagnostic scalar",
        ))
    }
}

fn macro_value(name: &str, value: &str) -> Result<()> {
    let name = CString::new(name).map_err(|_| invalid_argument("macro name contains NUL"))?;
    let value = CString::new(value).map_err(|_| invalid_argument("macro value contains NUL"))?;
    let return_code = unsafe { ferank_spi_macro_save(name.as_ptr(), value.as_ptr()) };
    if return_code == 0 {
        Ok(())
    } else {
        Err(FerankError::new(
            ErrorCode::Plugin,
            "Stata could not store a diagnostic macro",
        ))
    }
}

fn display(message: &str) -> Result<()> {
    let message = CString::new(message).map_err(|_| invalid_argument("display contains NUL"))?;
    let return_code = unsafe { ferank_spi_display(message.as_ptr()) };
    if return_code == 0 {
        Ok(())
    } else {
        Err(FerankError::new(
            ErrorCode::Plugin,
            "Stata display service is unavailable",
        ))
    }
}

fn report_error(error: &FerankError) {
    let message = format!("ferank: {}\n", error.message());
    if let Ok(message) = CString::new(message) {
        unsafe {
            let _ = ferank_spi_error(message.as_ptr());
        }
    }
}

fn check_interrupt() -> Result<()> {
    let poll = unsafe { ferank_spi_poll() };
    let stopped = unsafe { ferank_spi_stop_requested() };
    if poll != 0 || stopped != 0 {
        Err(FerankError::new(
            ErrorCode::Interrupted,
            "computation interrupted",
        ))
    } else {
        Ok(())
    }
}

fn required<'a>(values: &'a BTreeMap<String, String>, key: &str) -> Result<&'a str> {
    values
        .get(key)
        .map(String::as_str)
        .ok_or_else(|| invalid_argument(format!("missing native option {key}")))
}

fn parse<T>(value: &str, label: &str) -> Result<T>
where
    T: std::str::FromStr,
{
    value
        .parse()
        .map_err(|_| invalid_argument(format!("invalid {label} value {value:?}")))
}

fn invalid_argument(message: impl Into<String>) -> FerankError {
    FerankError::new(ErrorCode::InvalidArgument, message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounded_selftest_passes() {
        assert!(selftest());
    }

    #[test]
    fn request_requires_an_explicit_method() {
        let arguments = vec!["component=largest".to_owned(), "normalize=mean".to_owned()];
        assert!(Request::parse("estimate-edge", &arguments).is_err());
    }
}
