#!/usr/bin/env python3
"""Normalize the PE/COFF linker timestamp for deterministic Windows assets."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


PE_SIGNATURE = b"PE\0\0"
COFF_TIMESTAMP_OFFSET = 8
MACHINE_AMD64 = 0x8664


def normalize(path: Path) -> None:
    data = bytearray(path.read_bytes())
    if len(data) < 0x40 or data[:2] != b"MZ":
        raise ValueError(f"{path} is not a PE file")
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    if pe_offset + 24 > len(data) or data[pe_offset : pe_offset + 4] != PE_SIGNATURE:
        raise ValueError(f"{path} has an invalid PE signature")
    machine = struct.unpack_from("<H", data, pe_offset + 4)[0]
    if machine != MACHINE_AMD64:
        raise ValueError(f"{path} is not an amd64 PE asset")
    struct.pack_into("<I", data, pe_offset + COFF_TIMESTAMP_OFFSET, 0)
    path.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    normalize(args.path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
