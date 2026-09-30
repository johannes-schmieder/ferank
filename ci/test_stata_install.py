#!/usr/bin/env python3
"""Install from the README into isolated PLUS, then run its exact examples."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_SOURCE = "https://raw.githubusercontent.com/johannes-schmieder/ferank/main/"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=PUBLIC_SOURCE)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for name in ["work", "ado", "examples", "stata-plus", "stata-personal", "stata-oldplace", "stata-site"]:
        (output / name).mkdir()
    blocks = re.findall(r"```stata\n(.*?)```", (ROOT / "README.md").read_text(), re.S)
    if len(blocks) != 3 or blocks[0].count(PUBLIC_SOURCE) != 1:
        raise RuntimeError("Expected the README install block and exactly two Stata examples")
    blocks[0] = blocks[0].replace(PUBLIC_SOURCE, args.source)
    for name, block in zip(["installation", "example1", "example2"], blocks):
        (output / "examples" / (name + ".do")).write_text(block)
    stata = os.environ.get("STATA_BIN", "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp")
    command = [sys.executable, str(ROOT / "ci/supervise_stata.py"),
               "--timeout-seconds", "600", "--process-json", str(output / "process.json"),
               "--stdout-log", str(output / "process.stdout.log"), "--cwd", str(output / "work"),
               "--", stata, "-q", "-b", "do", str(ROOT / "ci/stata_ci.do"),
               str(ROOT / "ci/stata_install.do"), str(output / "stata.status"),
               str(output / "stata.log"), "install", str(output / "work"), str(output),
               args.source, str(output / "ado"), str(output / "examples")]
    subprocess.run(command, check=True)
    process = json.loads((output / "process.json").read_text())
    status = dict(line.split("=", 1) for line in (output / "stata.status").read_text().splitlines())
    log = (output / "stata.log").read_text(errors="replace")
    if process["timed_out"] or process["process_rc"] != 0 or status.get("stata_rc") != "0" or status.get("completed") != "1":
        raise RuntimeError("Stata install test failed; inspect " + str(output / "stata.log"))
    if "FERANK ISOLATED INSTALL AND README EXAMPLES PASS" not in log:
        raise RuntimeError("Install test did not emit its PASS marker")
    installed_hashes = {}
    names = ["ferank.ado", "ferank_load.ado", "ferank_estat.ado", "ferank_run.ado",
             "ferank.sthlp", "ferank_postestimation.sthlp", "ferank_macos.plugin",
             "ferank_LICENSE.txt", "ferank_NOTICE.txt", "ferank_macos.plugin.sha256"]
    for name in names:
        copies = list((output / "ado").rglob(name))
        if len(copies) != 1 or copies[0].read_bytes() != (ROOT / "stata" / name).read_bytes():
            raise RuntimeError("Installed payload differs from tested source: " + name)
        installed_hashes[name] = hashlib.sha256(copies[0].read_bytes()).hexdigest()
    evidence = {"source": args.source, "tested_sha": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "status": "success", "stata_status": status, "installed_sha256": installed_hashes,
        "readme_examples": 2, "help_examples": 5}
    (output / "install-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("FERANK ISOLATED INSTALL PASS source=" + args.source)
    print("INSTALL_EVIDENCE=" + str(output / "install-evidence.json"))


if __name__ == "__main__":
    main()
