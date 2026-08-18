#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import struct
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("check_artifact_size.py")
SPEC = importlib.util.spec_from_file_location("moonjust_artifact_size", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
artifact_size = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(artifact_size)


def uleb(value: int) -> bytes:
    encoded = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            encoded.append(byte | 0x80)
        else:
            encoded.append(byte)
            return bytes(encoded)


class ArtifactSizeTest(unittest.TestCase):
    def test_wasm_sections_include_custom_names_and_encoded_size(self) -> None:
        custom = uleb(4) + b"name" + b"abc"
        code = b"\x00"
        module = b"\0asm\x01\0\0\0" + b"\x00" + uleb(len(custom)) + custom + b"\x0a" + uleb(len(code)) + code
        sections = artifact_size.wasm_sections(module)
        self.assertEqual([row["name"] for row in sections], ["custom:name", "code"])
        self.assertEqual(sum(int(row["encoded_bytes"]) for row in sections) + 8, len(module))

    def test_pe_sections_report_raw_and_virtual_sizes(self) -> None:
        data = bytearray(0x200)
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 0x80)
        data[0x80:0x84] = b"PE\0\0"
        struct.pack_into("<HHIIIHH", data, 0x84, 0x8664, 1, 0, 0, 0, 0, 0)
        struct.pack_into("<8sIIIIIIHHI", data, 0x98, b".text\0\0\0", 123, 0x1000, 128, 0x100, 0, 0, 0, 0, 0)
        sections = artifact_size.pe_sections(bytes(data))
        self.assertEqual(sections[0]["name"], ".text")
        self.assertEqual(sections[0]["virtual_bytes"], 123)
        self.assertEqual(sections[0]["bytes"], 128)

    def test_budget_distinguishes_target_from_hard_limit(self) -> None:
        record = {"bytes": 102}
        failures: list[str] = []
        artifact_size.apply_budget("native", record, 100, 1.05, 1.00, failures)
        self.assertFalse(record["within_engineering_target"])
        self.assertEqual(failures, [])
        record = {"bytes": 106}
        artifact_size.apply_budget("native", record, 100, 1.05, 1.00, failures)
        self.assertEqual(len(failures), 1)

    def test_section_diff_marks_large_growth_for_review(self) -> None:
        diff = artifact_size.section_diff(
            [{"name": ".text", "bytes": 200}],
            [{"name": ".text", "bytes": 100}],
        )
        assert diff is not None
        self.assertEqual(diff[0]["delta_bytes"], 100)
        self.assertTrue(diff[0]["requires_review"])


if __name__ == "__main__":
    unittest.main()
