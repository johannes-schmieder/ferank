from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CI_DIR = Path(__file__).resolve().parents[1]
TESTED_SHA = "a" * 40


class ReceiptTests(unittest.TestCase):
    @staticmethod
    def normal_process(**overrides: object) -> dict[str, object]:
        value: dict[str, object] = {
            "started_at": "2026-01-01T00:00:00Z",
            "completed_at": "2026-01-01T00:00:01Z",
            "duration_seconds": 1.0,
            "launch_error": None,
            "timed_out": False,
            "process_rc": 0,
        }
        value.update(overrides)
        return value

    @staticmethod
    def status(stata_rc: int) -> str:
        return (
            "schema_version=1\nprofile=smoke\n"
            f"stata_rc={stata_rc}\n"
            "stata_version=18\nstata_edition=MP\nstata_os=MacOSX\n"
            "stata_machine_type=Mac (Apple Silicon)\nstata_processors=8\n"
            f"tests_passed={int(stata_rc == 0)}\n"
            f"tests_failed={int(stata_rc != 0)}\ncompleted=1\n"
        )

    def build_receipt(
        self,
        *,
        process: dict[str, object],
        status: str | None,
        log: str = "PASS_MARKER\n",
    ) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "process.json").write_text(json.dumps(process), encoding="utf-8")
            if status is not None:
                (root / "stata.status").write_text(status, encoding="utf-8")
            if log:
                (root / "stata.log").write_text(log, encoding="utf-8")
            (root / "profiles.json").write_text(
                json.dumps(
                    {
                        "profiles": {
                            "smoke": {
                                "suite": "ci/stata_smoke.do",
                                "required_log_markers": ["PASS_MARKER"],
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            receipt_path = root / "receipt.json"
            subprocess.run(
                [
                    sys.executable,
                    str(CI_DIR / "make_stata_receipt.py"),
                    "--profile-config",
                    str(root / "profiles.json"),
                    "--profile",
                    "smoke",
                    "--process-json",
                    str(root / "process.json"),
                    "--status-file",
                    str(root / "stata.status"),
                    "--run-dir",
                    str(root),
                    "--receipt",
                    str(receipt_path),
                    "--tested-sha",
                    TESTED_SHA,
                    "--stata-executable",
                    "/Applications/Stata/StataMP.app/Contents/MacOS/stata-mp",
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            return json.loads(receipt_path.read_text(encoding="utf-8"))

    def test_success(self) -> None:
        receipt = self.build_receipt(
            process=self.normal_process(), status=self.status(0)
        )
        self.assertEqual(receipt["status"], "success")
        self.assertEqual(receipt["stata_status"], "success")
        self.assertEqual(receipt["rust_status"], "not_run")
        self.assertEqual(receipt["tested_sha"], TESTED_SHA)

    def test_stata_error_wins_over_zero_process_rc(self) -> None:
        receipt = self.build_receipt(
            process=self.normal_process(process_rc=0), status=self.status(9)
        )
        self.assertEqual(receipt["failure_kind"], "stata_error")
        self.assertEqual(receipt["stata_rc"], 9)

    def test_launch_timeout_crash_and_missing_outputs(self) -> None:
        cases = (
            (self.normal_process(process_rc=None, launch_error="missing"), None, "launch_error"),
            (self.normal_process(process_rc=-15, timed_out=True), None, "timeout"),
            (self.normal_process(process_rc=-9), None, "crash"),
            (self.normal_process(), None, "missing_status"),
        )
        for process, status, expected in cases:
            with self.subTest(expected=expected):
                receipt = self.build_receipt(process=process, status=status)
                self.assertEqual(receipt["failure_kind"], expected)

    def test_missing_marker(self) -> None:
        receipt = self.build_receipt(
            process=self.normal_process(), status=self.status(0), log="OTHER\n"
        )
        self.assertEqual(receipt["failure_kind"], "missing_marker")


class AugmentTests(unittest.TestCase):
    def augment(self, rust_rc: int) -> dict[str, object]:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            receipt = root / "receipt.json"
            receipt.write_text(
                json.dumps({"status": "success", "stata_status": "success"}),
                encoding="utf-8",
            )
            status = root / "rust.status"
            status.write_text(
                "schema_version=1\n"
                f"rust_status={'success' if rust_rc == 0 else 'failure'}\n"
                f"rust_rc={rust_rc}\nrust_mode=toolchain-smoke\n"
                "rust_toolchain=stable-aarch64-apple-darwin\n"
                "rustc_version=rustc 1.97.1\ncompleted=1\n",
                encoding="utf-8",
            )
            subprocess.run(
                [
                    sys.executable,
                    str(CI_DIR / "augment_ci_receipt.py"),
                    str(receipt),
                    str(status),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            return json.loads(receipt.read_text(encoding="utf-8"))

    def test_rust_success_completes_combined_receipt(self) -> None:
        value = self.augment(0)
        self.assertEqual(value["status"], "success")
        self.assertEqual(value["rust_status"], "success")
        self.assertEqual(value["rust_mode"], "toolchain-smoke")

    def test_rust_failure_changes_combined_status(self) -> None:
        value = self.augment(7)
        self.assertEqual(value["status"], "failure")
        self.assertEqual(value["rust_status"], "failure")
        self.assertEqual(value["failure_kind"], "rust_error")


if __name__ == "__main__":
    unittest.main()
