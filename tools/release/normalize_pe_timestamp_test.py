from __future__ import annotations

import importlib.util
import struct
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("normalize_pe_timestamp.py")
SPEC = importlib.util.spec_from_file_location("moonjust_normalize_pe", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
normalize_pe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(normalize_pe)


class NormalizePeTimestampTest(unittest.TestCase):
    def test_normalizes_pe_timestamps(self) -> None:
        data = bytearray(1024)
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 64)
        data[64:68] = b"PE\0\0"
        struct.pack_into("<H", data, 68, normalize_pe.MACHINE_AMD64)
        struct.pack_into("<I", data, 72, 0x12345678)
        struct.pack_into("<H", data, 70, 1)
        struct.pack_into("<H", data, 84, 240)
        optional = 88
        struct.pack_into("<H", data, optional, normalize_pe.PE32_PLUS_MAGIC)
        struct.pack_into("<I", data, optional + 108, 16)
        debug_directory = optional + 112 + 6 * 8
        struct.pack_into("<II", data, debug_directory, 0x1000, 28)
        section = optional + 240
        struct.pack_into("<IIII", data, section + 8, 0x1000, 0x1000, 0x200, 0x200)
        struct.pack_into("<I", data, 0x204, 0x87654321)
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "just.exe"
            path.write_bytes(data)
            normalize_pe.normalize(path)
            normalized = path.read_bytes()
            self.assertEqual(struct.unpack_from("<I", normalized, 72)[0], 0)
            self.assertEqual(struct.unpack_from("<I", normalized, 0x204)[0], 0)

    def test_rejects_non_pe_input(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "not-exe"
            path.write_bytes(b"not a PE")
            with self.assertRaises(ValueError):
                normalize_pe.normalize(path)


if __name__ == "__main__":
    unittest.main()
