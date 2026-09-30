#!/usr/bin/env python3
"""Run the private full-panel Stata benchmark with pinned local package snapshots."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import time

INPUT_SHA = "e4a1928d98c1dbe7185634e14470b9361b58f8d5b33cceacc8d168ccdad4634e"
ROOT = Path(__file__).resolve().parents[1]


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command(args: list[str]) -> str:
    return subprocess.check_output(args, text=True).strip()


def state(root: Path) -> dict:
    return {"revision": command(["git", "-C", str(root), "rev-parse", "HEAD"]),
            "status": command(["git", "-C", str(root), "status", "--short"])}


def snapshot(root: Path, target: Path, package: str) -> dict:
    before = state(root)
    paths = list((root / "stata").glob("*.ado"))
    paths += list((root / "stata").glob("*.sthlp"))
    plugin_name = f"{package}_macos.plugin"
    plugin = root / "dist" / plugin_name
    if not plugin.is_file():
        plugin = root / "stata" / plugin_name
    if not plugin.is_file():
        raise FileNotFoundError(plugin)
    paths.append(plugin)
    if package == "ferank":
        paths += [root / "bench/veneto_full.do", root / "bench/veneto_report.do"]
    files = {}
    for source in paths:
        relative = source.relative_to(root)
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        files[str(relative)] = sha(destination)
        if files[str(relative)] != sha(source):
            raise RuntimeError(f"Source changed while staging {relative}; no estimation started")
    if state(root) != before:
        raise RuntimeError(f"{package} source changed while staging; no estimation started")
    return {**before, "files": files, "plugin_sha256": sha(plugin)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fereg-root", type=Path, default=ROOT.parent / "fereg")
    parser.add_argument("--stata", default="/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp")
    parser.add_argument("--threads", nargs="+", type=int, default=[1, 8])
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--report-only", action="store_true")
    parser.add_argument("--sample", choices=["sorkin", "full"], default="sorkin",
                        help="sorkin: >=90 nonsingleton person-years then largest directed SCC")
    args = parser.parse_args()
    source = args.input.resolve()
    out = args.output.resolve()
    if ROOT == source or ROOT in source.parents:
        raise ValueError("The licensed input must remain outside the repository")
    if args.repetitions < 3 or any(t < 1 or t > 16 for t in args.threads):
        raise ValueError("Use at least three repeats and native thread requests in 1--16")
    out.mkdir(parents=True, exist_ok=True, mode=0o700)
    out.chmod(0o700)
    staged = out / "snapshots"
    ferank_runtime = staged / "ferank"
    if args.report_only:
        if not (out / "timings.dta").is_file():
            raise FileNotFoundError("No existing timings to render")
        ferank_runtime = out / "report_code/ferank"
        shutil.copytree(staged / "ferank", ferank_runtime, dirs_exist_ok=True)
        shutil.copy2(ROOT / "bench/veneto_report.do", ferank_runtime / "bench/veneto_report.do")
        shutil.copy2(ROOT / "bench/veneto_full.do", ferank_runtime / "bench/veneto_full.do")
    else:
        if (out / "run_manifest.json").exists():
            raise FileExistsError("Use a fresh output directory to preserve prior benchmark evidence")
        if sha(source) != INPUT_SHA:
            raise ValueError("Input differs from the validated full FEVC Veneto panel")
        sources = {name: snapshot(root, staged / name, name) for name, root in
                   [("ferank", ROOT), ("fereg", args.fereg_root.resolve())]}
        latexlog = Path(os.environ.get("LATEXLOG_DIR", str(Path.home() /
            "Library/Application Support/Stata/ado/plus/l"))) / "latexlog.ado"
        destination = staged / "latexlog/latexlog.ado"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(latexlog, destination)
        manifest = {"input_sha256": INPUT_SHA, "input_bytes": source.stat().st_size,
                    "sources": sources, "latexlog_sha256": sha(destination),
                    "hardware": command(["sysctl", "-n", "hw.model", "hw.memsize", "hw.ncpu"]),
                    "cpu_brand": command(["sysctl", "-n", "machdep.cpu.brand_string"]),
                    "platform": platform.platform(), "load_before": os.getloadavg(),
                    "repetitions": args.repetitions, "threads": args.threads,
                    "sample_profile": args.sample,
                    "sample_rule": "Original-panel firm count >=90 rows with a later worker observation, then largest directed SCC" if args.sample == "sorkin" else "Complete prepared panel",
                    "comparison_weights": "firm person-years in the estimation panel",
                    "sample_selection_boundary": "SCC selection and sample restriction excluded from command timers; selection loads ferank before timing in sorkin mode",
                    "timing_boundary": "complete Stata estimation command; data import excluded",
                    "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
        (out / "run_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    recorded = json.loads((out / "run_manifest.json").read_text())
    if "cpu_brand" not in recorded:
        recorded_model = recorded["hardware"].splitlines()[0]
        if command(["sysctl", "-n", "hw.model"]) != recorded_model:
            raise RuntimeError("Original CPU metadata unavailable on this other host")
        recorded["cpu_brand"] = command(["sysctl", "-n", "machdep.cpu.brand_string"])
        (out / "run_manifest.json").write_text(json.dumps(recorded, indent=2) + "\n")
    memory_gib = int(recorded["hardware"].splitlines()[1]) / (1024 ** 3)
    (out / "hardware.txt").write_text(f"{recorded['cpu_brand']}\n{memory_gib:g}\n")
    mode = "report" if args.report_only else "full"
    environment = dict(os.environ, LATEXLOG_DIR=str(staged / "latexlog"))
    # Stata's batch argument parser needs literal quotes around paths/word lists.
    arguments = [str(ferank_runtime / "bench/veneto_full.do"), str(source), str(out),
                 str(staged / "fereg"), str(ferank_runtime), str(args.repetitions),
                 " ".join(map(str, args.threads)), mode, args.sample]
    argv = [args.stata, "-q", "-b", "do"] + [f'"{value}"' for value in arguments]
    print(f"Starting full Veneto {mode}; output: {out}", flush=True)
    started = time.perf_counter()
    with (out / f"launcher_{mode}.log").open("w") as log:
        result = subprocess.run(argv, cwd=out, env=environment, stdout=log, stderr=subprocess.STDOUT)
    statusfile = out / f"stata_{mode}.status"
    status = int(statusfile.read_text().strip()) if statusfile.exists() else None
    text = (out / f"stata_{mode}.log").read_text() if (out / f"stata_{mode}.log").exists() else ""
    execution = {"process_rc": result.returncode, "stata_rc": status,
                 "whole_process_seconds": time.perf_counter() - started,
                 "load_after": os.getloadavg(), "mode": mode,
                 "report_source_sha256": sha(ferank_runtime / "bench/veneto_report.do"),
                 "report_pass": any(line.startswith("FERANK FULL VENETO REPORT PASS") for line in text.splitlines())}
    (out / ("execution_report.json" if args.report_only else "execution.json")).write_text(
        json.dumps(execution, indent=2) + "\n")
    if result.returncode or status != 0 or not execution["report_pass"]:
        raise RuntimeError(f"Stata failed or lacked its PASS marker; inspect {out / ('stata_' + mode + '.log')}")
    pdf = out / "veneto_benchmark.pdf"
    if not pdf.exists() or pdf.stat().st_size < 1000:
        raise RuntimeError("PDF missing or empty")
    print(json.dumps(execution), flush=True)
    print(f"Report: {pdf}", flush=True)


if __name__ == "__main__":
    main()
