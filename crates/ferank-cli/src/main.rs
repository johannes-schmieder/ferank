//! Bounded validation and benchmark driver for `ferank-core`.

use ferank_core::{
    canonicalize_edges, estimate_bradley_terry, estimate_sorkin, BradleyTerryOptions,
    ComponentSelection, EdgeInput, GraphOptions, Normalization, SolverOptions, SorkinOptions,
};
use std::time::Instant;

fn main() {
    let mut arguments = std::env::args().skip(1);
    let action = arguments.next().unwrap_or_else(|| "selftest".to_owned());
    let result = match action.as_str() {
        "selftest" => selftest(),
        "version" => {
            println!("ferank-cli {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        "bench" => {
            let benchmark_arguments = arguments.collect::<Vec<_>>();
            benchmark(&benchmark_arguments)
        }
        _ => Err(format!(
            "unknown action {action:?}; expected selftest, bench, or version"
        )),
    };
    if let Err(message) = result {
        eprintln!("ferank-cli: {message}");
        std::process::exit(1);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BenchmarkMethod {
    Sorkin,
    BradleyTerry,
    Both,
}

#[derive(Debug, Clone, Copy)]
struct BenchmarkOptions {
    firms: usize,
    edges: usize,
    threads: usize,
    method: BenchmarkMethod,
}

impl Default for BenchmarkOptions {
    fn default() -> Self {
        Self {
            firms: 10_000,
            edges: 100_000,
            threads: 1,
            method: BenchmarkMethod::Both,
        }
    }
}

fn benchmark(arguments: &[String]) -> std::result::Result<(), String> {
    let options = parse_benchmark_options(arguments)?;
    if options.firms < 2 {
        return Err("--firms must be at least two".to_owned());
    }
    if options.edges < 2 * options.firms {
        return Err("--edges must be at least twice --firms".to_owned());
    }

    let generation_start = Instant::now();
    let rows = synthetic_edges(options.firms, options.edges);
    let generation_seconds = generation_start.elapsed().as_secs_f64();
    let canonical_start = Instant::now();
    let graph =
        canonicalize_edges(&rows, GraphOptions::default()).map_err(|error| error.to_string())?;
    let canonical_seconds = canonical_start.elapsed().as_secs_f64();
    println!(
        "FERANK_BENCH_INPUT firms={} requested_edges={} canonical_edges={} threads={}",
        graph.firm_ids.len(),
        options.edges,
        graph.edges.len(),
        options.threads
    );
    println!("FERANK_BENCH_PHASE phase=generation seconds={generation_seconds:.6}");
    println!("FERANK_BENCH_PHASE phase=canonicalization_scc seconds={canonical_seconds:.6}");

    let solver = SolverOptions {
        tolerance: 1e-9,
        max_iterations: 20_000,
        threads: options.threads,
    };
    if matches!(
        options.method,
        BenchmarkMethod::Sorkin | BenchmarkMethod::Both
    ) {
        let started = Instant::now();
        let result = estimate_sorkin(
            &graph,
            ComponentSelection::Largest,
            &Normalization::Mean,
            SorkinOptions { solver, lazy: 0.5 },
        )
        .map_err(|error| error.to_string())?;
        let seconds = started.elapsed().as_secs_f64();
        println!(
            "FERANK_BENCH_SOLVE method=sorkin seconds={seconds:.6} results={} diagnostics={}",
            result.firms.len(),
            result.diagnostics.len()
        );
    }
    if matches!(
        options.method,
        BenchmarkMethod::BradleyTerry | BenchmarkMethod::Both
    ) {
        let started = Instant::now();
        let result = estimate_bradley_terry(
            &graph,
            ComponentSelection::Largest,
            &Normalization::Mean,
            BradleyTerryOptions {
                solver,
                ..BradleyTerryOptions::default()
            },
        )
        .map_err(|error| error.to_string())?;
        let seconds = started.elapsed().as_secs_f64();
        println!(
            "FERANK_BENCH_SOLVE method=bradleyterry seconds={seconds:.6} results={} diagnostics={}",
            result.firms.len(),
            result.diagnostics.len()
        );
    }
    println!("FERANK_BENCH_PASS");
    Ok(())
}

fn parse_benchmark_options(arguments: &[String]) -> std::result::Result<BenchmarkOptions, String> {
    let mut options = BenchmarkOptions::default();
    let mut index = 0;
    while index < arguments.len() {
        let option = arguments[index].as_str();
        let value = arguments
            .get(index + 1)
            .ok_or_else(|| format!("missing value for {option}"))?;
        match option {
            "--firms" => options.firms = parse_positive(value, option)?,
            "--edges" => options.edges = parse_positive(value, option)?,
            "--threads" => options.threads = parse_positive(value, option)?,
            "--method" => {
                options.method = match value.as_str() {
                    "sorkin" => BenchmarkMethod::Sorkin,
                    "bradleyterry" => BenchmarkMethod::BradleyTerry,
                    "both" => BenchmarkMethod::Both,
                    _ => return Err("--method must be sorkin, bradleyterry, or both".to_owned()),
                };
            }
            _ => return Err(format!("unknown benchmark option {option:?}")),
        }
        index += 2;
    }
    Ok(options)
}

fn parse_positive(value: &str, option: &str) -> std::result::Result<usize, String> {
    value
        .parse::<usize>()
        .ok()
        .filter(|parsed| *parsed > 0)
        .ok_or_else(|| format!("{option} requires a positive integer"))
}

fn synthetic_edges(firms: usize, edges: usize) -> Vec<EdgeInput> {
    let mut rows = Vec::with_capacity(edges);
    for firm in 0..firms {
        rows.push(edge(
            (firm + 1) as f64,
            ((firm + 1) % firms + 1) as f64,
            1.0 + (firm % 7) as f64 / 10.0,
        ));
        rows.push(edge(
            ((firm + 1) % firms + 1) as f64,
            (firm + 1) as f64,
            1.0 + (firm % 11) as f64 / 10.0,
        ));
    }
    let mut state = 0x4d59_5df4_d0f3_3173_u64;
    while rows.len() < edges {
        state = splitmix64(state);
        let origin = usize::try_from(state % firms as u64).expect("modulo fits usize");
        state = splitmix64(state);
        let mut destination = usize::try_from(state % firms as u64).expect("modulo fits usize");
        if destination == origin {
            destination = (destination + 1) % firms;
        }
        state = splitmix64(state);
        let flow = 0.5 + (state % 1_000) as f64 / 1_000.0;
        rows.push(edge((origin + 1) as f64, (destination + 1) as f64, flow));
    }
    rows
}

const fn splitmix64(mut value: u64) -> u64 {
    value = value.wrapping_add(0x9e37_79b9_7f4a_7c15);
    value = (value ^ (value >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value = (value ^ (value >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^ (value >> 31)
}

fn selftest() -> std::result::Result<(), String> {
    let rows = [
        edge(1.0, 2.0, 4.0),
        edge(2.0, 1.0, 1.0),
        edge(2.0, 3.0, 3.0),
        edge(3.0, 2.0, 1.0),
        edge(3.0, 1.0, 2.0),
        edge(1.0, 3.0, 1.0),
    ];
    let graph =
        canonicalize_edges(&rows, GraphOptions::default()).map_err(|error| error.to_string())?;
    let sorkin = estimate_sorkin(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        SorkinOptions::default(),
    )
    .map_err(|error| error.to_string())?;
    let bradley_terry = estimate_bradley_terry(
        &graph,
        ComponentSelection::Largest,
        &Normalization::Mean,
        BradleyTerryOptions::default(),
    )
    .map_err(|error| error.to_string())?;
    if sorkin.firms.len() != 3 || bradley_terry.firms.len() != 3 {
        return Err("unexpected fixture result size".to_owned());
    }
    println!("FERANK_CORE_SELFTEST_PASS");
    Ok(())
}

const fn edge(origin: f64, destination: f64, flow: f64) -> EdgeInput {
    EdgeInput {
        origin,
        destination,
        flow,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn synthetic_benchmark_graph_is_exact_size_and_connected() {
        let rows = synthetic_edges(20, 100);
        assert_eq!(rows.len(), 100);
        let graph = canonicalize_edges(&rows, GraphOptions::default()).unwrap();
        assert_eq!(graph.firm_ids.len(), 20);
        assert_eq!(graph.components.len(), 1);
    }

    #[test]
    fn benchmark_options_are_strict() {
        let options = parse_benchmark_options(&[
            "--firms".to_owned(),
            "100".to_owned(),
            "--method".to_owned(),
            "sorkin".to_owned(),
        ])
        .unwrap();
        assert_eq!(options.firms, 100);
        assert_eq!(options.method, BenchmarkMethod::Sorkin);
        assert!(parse_benchmark_options(&["--bogus".to_owned(), "1".to_owned()]).is_err());
    }
}
