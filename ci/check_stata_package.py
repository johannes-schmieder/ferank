#!/usr/bin/env python3
"""Validate the public Stata manifests, notices and Mac binary checksum."""

import hashlib
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = {"MACARM64", "OSX.ARM64", "MACINTEL64", "OSX.X8664"}


def check_manifest(path):
    platform_files = {}
    required = []
    for line in path.read_text().splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] in {"f", "F"}:
            assert len(fields) == 2, line
            assert not Path(fields[1]).name.startswith("_"), line
            assert (path.parent / fields[1]).is_file(), line
        elif fields[0] in {"g", "G"}:
            assert len(fields) == 3, line
            assert not Path(fields[2]).name.startswith("_"), line
            assert (path.parent / fields[2]).is_file(), line
            assert fields[1] not in platform_files, line
            platform_files[fields[1]] = Path(fields[2]).name
        elif fields[0] == "h":
            assert not Path(fields[1]).name.startswith("_"), line
            required.append(fields[1])
    assert set(platform_files) == PLATFORMS, platform_files
    assert set(platform_files.values()) == {"ferank_macos.plugin"}
    assert required == ["ferank_macos.plugin"], required


def main():
    check_manifest(ROOT / "ferank.pkg")
    check_manifest(ROOT / "stata/ferank.pkg")
    for original, installed in [("LICENSE", "ferank_LICENSE.txt"),
                                ("NOTICE.md", "ferank_NOTICE.txt")]:
        assert (ROOT / original).read_bytes() == (ROOT / "stata" / installed).read_bytes()
    binary = (ROOT / "stata/ferank_macos.plugin").read_bytes()
    recorded = (ROOT / "stata/ferank_macos.plugin.sha256").read_text().split()
    assert recorded == [hashlib.sha256(binary).hexdigest(), "ferank_macos.plugin"]
    magic, count = struct.unpack_from(">II", binary)
    assert magic == 0xCAFEBABE and count == 2, "Expected a universal Mach-O binary"
    architectures = {struct.unpack_from(">I", binary, 8 + 20*i)[0] for i in range(count)}
    assert architectures == {0x01000007, 0x0100000C}, architectures
    print("FERANK STATA DISTRIBUTION PASS")


if __name__ == "__main__":
    main()
