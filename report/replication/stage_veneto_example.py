#!/usr/bin/env python3
"""Stage and hash-verify the public Veneto-based LeaveOutKSS example."""

from __future__ import annotations

import argparse
import hashlib
import io
import tarfile
import urllib.request
from pathlib import Path


REPORT_ROOT = Path(__file__).resolve().parents[1]
DESTINATION = REPORT_ROOT / "data/external/kss_example_1999_2001.csv"
EXPECTED_SHA256 = "93e57a413a8cfccdcb043c5d793105a67b2dc9ebd27d5d3a4f1800abf89a2241"
ARCHIVE_URL = "https://cran.r-project.org/src/contrib/LeaveOutKSS_0.1.0.tar.gz"
ARCHIVE_MEMBER_SUFFIX = "/inst/extdata/test.csv"


def normalized(payload: bytes) -> bytes:
    return payload.replace(b"\r\n", b"\n").replace(b"\r", b"\n")


def extract_archive(payload: bytes) -> bytes:
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as archive:
        members = [
            member
            for member in archive.getmembers()
            if member.isfile() and member.name.endswith(ARCHIVE_MEMBER_SUFFIX)
        ]
        if len(members) != 1:
            raise RuntimeError(
                f"expected one {ARCHIVE_MEMBER_SUFFIX} member, found {len(members)}"
            )
        handle = archive.extractfile(members[0])
        if handle is None:
            raise RuntimeError("the Veneto example could not be extracted")
        return handle.read()


def source_bytes(source: Path | None) -> bytes:
    if source is not None:
        payload = source.read_bytes()
        return extract_archive(payload) if source.name.endswith((".tar.gz", ".tgz")) else payload
    with urllib.request.urlopen(ARCHIVE_URL, timeout=60) as response:
        return extract_archive(response.read())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path)
    parser.add_argument("--destination", type=Path, default=DESTINATION)
    arguments = parser.parse_args()

    payload = normalized(source_bytes(arguments.source))
    digest = hashlib.sha256(payload).hexdigest()
    if digest != EXPECTED_SHA256:
        raise RuntimeError(
            f"Veneto example hash mismatch: expected {EXPECTED_SHA256}, found {digest}"
        )
    arguments.destination.parent.mkdir(parents=True, exist_ok=True)
    arguments.destination.write_bytes(payload)
    print(f"{digest}  {arguments.destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
