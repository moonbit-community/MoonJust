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
    def test_normalizes_amd64_coff_timestamp(self) -> None:
        data = bytearray(128)
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 64)
        data[64:68] = b"PE\0\0"
        struct.pack_into("<H", data, 68, normalize_pe.MACHINE_AMD64)
        struct.pack_into("<I", data, 72, 0x12345678)
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "just.exe"
            path.write_bytes(data)
            normalize_pe.normalize(path)
            self.assertEqual(struct.unpack_from("<I", path.read_bytes(), 72)[0], 0)

    def test_rejects_non_pe_input(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "not-exe"
            path.write_bytes(b"not a PE")
            with self.assertRaises(ValueError):
                normalize_pe.normalize(path)


if __name__ == "__main__":
    unittest.main()
