#!/usr/bin/env python3
"""Stage tracked source, run one licensed-Stata profile, and emit a receipt."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


DEFAULT_STATA = Path("/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp")


def command_output(command: list[str], cwd: Path) -> str:
    return subprocess.check_output(command, cwd=cwd, text=True).strip()


def repo_root() -> Path:
    return Path(
        command_output(["git", "rev-parse", "--show-toplevel"], Path.cwd())
    ).resolve()


def tracked_files(root: Path) -> list[Path]:
    raw = subprocess.check_output(["git", "ls-files", "--cached", "-z"], cwd=root)
    files: list[Path] = []
    for name in raw.split(b"\0"):
        if not name:
            continue
        relative = Path(os.fsdecode(name))
        source = (root / relative).resolve()
        if source.is_file() and source.is_relative_to(root):
            files.append(relative)
    return files


def stage_repository(root: Path, destination: Path) -> None:
    for relative in tracked_files(root):
        source = root / relative
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def clear_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    for child in path.iterdir():
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink()


def bundle_version(stata_executable: Path) -> str:
    info_plist = stata_executable.parents[1] / "Info.plist"
    try:
        with info_plist.open("rb") as handle:
            value = plistlib.load(handle).get("CFBundleShortVersionString")
    except (OSError, plistlib.InvalidFileException):
        return "unknown"
    return str(value) if value is not None else "unknown"


def seed_stata_plus(config: dict[str, object], run_root: Path) -> None:
    source_root = Path(
        os.environ.get(
            "STATA_PLUS_SOURCE", "~/Library/Application Support/Stata/ado/plus"
        )
    ).expanduser().resolve()
    destination_root = (run_root / "stata-plus").resolve()
    entries = config.get("stata_plus_files", [])
    if not isinstance(entries, list):
        raise ValueError("stata_plus_files must be a list")
    for raw_name in entries:
        if not isinstance(raw_name, str):
            raise ValueError("stata_plus_files entries must be strings")
        relative = Path(raw_name)
        source = (source_root / relative).resolve()
        destination = (destination_root / relative).resolve()
        if not source.is_relative_to(source_root) or not destination.is_relative_to(
            destination_root
        ):
            raise ValueError(f"unsafe Stata PLUS dependency path: {raw_name}")
        if not source.is_file():
            raise FileNotFoundError(f"required Stata dependency is missing: {raw_name}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def copy_evidence(run_root: Path, artifact_dir: Path) -> None:
    for source in sorted(run_root.iterdir()):
        # Stata's process stdout can contain the startup/license banner.  The
        # explicit text log begins after startup and is the safe artifact.
        if not source.is_file():
            continue
        if source.name == "process.stdout.log":
            continue
        if source.suffix == ".log" and source.name != "stata.log":
            continue
        shutil.copy2(source, artifact_dir / source.name)


def tail(path: Path, lines: int = 100) -> str:
    try:
        values = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    return "\n".join(values[-lines:])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("profile", nargs="?", default="smoke")
    args = parser.parse_args()

    root = repo_root()
    config_path = root / "ci" / "stata_profiles.json"
    config = json.loads(config_path.read_text(encoding="utf-8"))
    profiles = config.get("profiles", {})
    if args.profile not in profiles:
        choices = ", ".join(sorted(profiles))
        parser.error(f"unknown profile {args.profile!r}; choose one of: {choices}")
    profile = profiles[args.profile]

    artifact_dir = root / ".ci" / "stata" / "run"
    clear_directory(artifact_dir)
    parent = Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir())).resolve()
    parent.mkdir(parents=True, exist_ok=True)
    run_root = Path(
        tempfile.mkdtemp(prefix="texpdf-stata-ci-", dir=parent)
    )
    staged_root = run_root / "repo"
    staged_root.mkdir()
    stage_repository(root, staged_root)
    for directory in (
        "stata-plus",
        "stata-personal",
        "stata-oldplace",
        "stata-site",
        "output",
    ):
        (run_root / directory).mkdir()
    seed_stata_plus(config, run_root)

    tested_sha = os.environ.get("GITHUB_SHA") or command_output(
        ["git", "rev-parse", "HEAD"], root
    )
    stata_executable = Path(
        os.environ.get("STATA_BIN", str(DEFAULT_STATA))
    ).expanduser().resolve()
    status_file = run_root / "stata.status"
    stata_log = run_root / "stata.log"
    process_json = run_root / "process.json"
    process_log = run_root / "process.stdout.log"
    timeout_seconds = int(profile["timeout_seconds"])
    raw_arguments = profile.get("arguments", [])
    if not isinstance(raw_arguments, list):
        raise ValueError("profile arguments must be a list")
    replacements = {"repo_root": str(staged_root), "run_root": str(run_root)}
    suite_arguments = [str(value).format(**replacements) for value in raw_arguments]

    stata_command = [
        str(stata_executable),
        "-q",
        "-b",
        "do",
        str(staged_root / "ci" / "stata_ci.do"),
        str(staged_root / str(profile["suite"])),
        str(status_file),
        str(stata_log),
        args.profile,
        str(staged_root),
        str(run_root),
        *suite_arguments,
    ]
    supervisor = [
        sys.executable,
        str(staged_root / "ci" / "supervise_stata.py"),
        "--timeout-seconds",
        str(timeout_seconds),
        "--process-json",
        str(process_json),
        "--stdout-log",
        str(process_log),
        "--cwd",
        str(run_root),
        "--",
        *stata_command,
    ]
    supervisor_rc = subprocess.run(supervisor, check=False).returncode
    if supervisor_rc != 0 and not process_json.exists():
        process_json.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "started_at": None,
                    "completed_at": None,
                    "duration_seconds": None,
                    "process_rc": supervisor_rc,
                    "timed_out": False,
                    "launch_error": (
                        f"Stata supervisor exited with code {supervisor_rc}"
                    ),
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )

    copy_evidence(run_root, artifact_dir)
    receipt_path = artifact_dir / "receipt.json"
    make_receipt = [
        sys.executable,
        str(staged_root / "ci" / "make_stata_receipt.py"),
        "--profile-config",
        str(staged_root / "ci" / "stata_profiles.json"),
        "--profile",
        args.profile,
        "--process-json",
        str(process_json),
        "--status-file",
        str(status_file),
        "--run-dir",
        str(run_root),
        "--receipt",
        str(receipt_path),
        "--tested-sha",
        tested_sha,
        "--repository",
        os.environ.get("GITHUB_REPOSITORY", "local/texpdf"),
        "--ref",
        os.environ.get("GITHUB_REF", "local"),
        "--run-id",
        os.environ.get("GITHUB_RUN_ID", "local"),
        "--run-attempt",
        os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "--runner-name",
        os.environ.get("RUNNER_NAME", "local-mac"),
        "--stata-executable",
        str(stata_executable),
        "--stata-bundle-version",
        bundle_version(stata_executable),
    ]
    receipt_rc = subprocess.run(make_receipt, check=False).returncode
    copy_evidence(run_root, artifact_dir)

    if os.environ.get("STATA_CI_KEEP_TEMP") == "1":
        print(f"STATA_CI_TEMP={run_root}")
    else:
        shutil.rmtree(run_root)

    if receipt_rc != 0:
        return receipt_rc
    checker = [
        sys.executable,
        str(root / "ci" / "check_stata_receipt.py"),
        str(receipt_path),
        "--expect-tested-sha",
        tested_sha,
        "--expect-profile",
        args.profile,
        "--require-success",
    ]
    checker_result = subprocess.run(checker, check=False)
    if checker_result.returncode != 0:
        log_tail = tail(artifact_dir / "stata.log")
        if log_tail:
            print("--- CI log tail ---", file=sys.stderr)
            print(log_tail, file=sys.stderr)
    return checker_result.returncode


if __name__ == "__main__":
    sys.exit(main())
