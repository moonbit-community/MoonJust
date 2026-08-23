#!/usr/bin/env python3
"""Normalize PE linker timestamps for deterministic Windows assets."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


PE_SIGNATURE = b"PE\0\0"
COFF_TIMESTAMP_OFFSET = 8
MACHINE_AMD64 = 0x8664
PE32_PLUS_MAGIC = 0x20B
SECTION_HEADER_SIZE = 40
DEBUG_DIRECTORY_ENTRY_SIZE = 28
DATA_DIRECTORY_COUNT_OFFSET = 108
DATA_DIRECTORY_OFFSET = 112
EXPORT_DIRECTORY_INDEX = 0
DEBUG_DIRECTORY_INDEX = 6


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
    coff_offset = pe_offset + 4
    number_of_sections = struct.unpack_from("<H", data, coff_offset + 2)[0]
    optional_size = struct.unpack_from("<H", data, coff_offset + 16)[0]
    optional_offset = pe_offset + 24
    if optional_offset + optional_size > len(data):
        raise ValueError(f"{path} has a truncated PE optional header")
    if struct.unpack_from("<H", data, optional_offset)[0] != PE32_PLUS_MAGIC:
        raise ValueError(f"{path} is not a PE32+ asset")
    struct.pack_into("<I", data, pe_offset + COFF_TIMESTAMP_OFFSET, 0)

    directory_count = struct.unpack_from(
        "<I", data, optional_offset + DATA_DIRECTORY_COUNT_OFFSET
    )[0]
    directory_count = min(directory_count, 16)
    section_offset = optional_offset + optional_size
    sections = []
    for index in range(number_of_sections):
        current = section_offset + index * SECTION_HEADER_SIZE
        if current + SECTION_HEADER_SIZE > len(data):
            raise ValueError(f"{path} has a truncated PE section table")
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from(
            "<IIII", data, current + 8
        )
        sections.append((virtual_address, max(virtual_size, raw_size), raw_offset, raw_size))

    def file_offset(rva: int) -> int:
        for virtual_address, span, raw_offset, raw_size in sections:
            if virtual_address <= rva < virtual_address + span:
                offset = raw_offset + (rva - virtual_address)
                if offset + 4 <= len(data) and offset < raw_offset + raw_size:
                    return offset
        raise ValueError(f"{path} has an unmapped PE directory RVA: 0x{rva:x}")

    directories = optional_offset + DATA_DIRECTORY_OFFSET
    if directory_count > EXPORT_DIRECTORY_INDEX:
        export_rva, export_size = struct.unpack_from(
            "<II", data, directories + EXPORT_DIRECTORY_INDEX * 8
        )
        if export_rva and export_size >= 8:
            struct.pack_into("<I", data, file_offset(export_rva) + 4, 0)
    if directory_count > DEBUG_DIRECTORY_INDEX:
        debug_rva, debug_size = struct.unpack_from(
            "<II", data, directories + DEBUG_DIRECTORY_INDEX * 8
        )
        if debug_rva and debug_size:
            if debug_size % DEBUG_DIRECTORY_ENTRY_SIZE:
                raise ValueError(f"{path} has a malformed PE debug directory")
            debug_offset = file_offset(debug_rva)
            for offset in range(0, debug_size, DEBUG_DIRECTORY_ENTRY_SIZE):
                struct.pack_into("<I", data, debug_offset + offset + 4, 0)
    path.write_bytes(data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    normalize(args.path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
