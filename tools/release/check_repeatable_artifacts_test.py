#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("check_repeatable_artifacts.py")
SPEC = importlib.util.spec_from_file_location("moonjust_repeatability", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
repeatability = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repeatability)


class RepeatabilityTest(unittest.TestCase):
    def test_pair_parser_preserves_paths(self) -> None:
        name, first, second = repeatability.parse_pair("native=first.bin=second.bin")
        self.assertEqual(name, "native")
        self.assertEqual(first.name, "first.bin")
        self.assertEqual(second.name, "second.bin")

    def test_hash_is_content_based(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            first = Path(raw) / "first"
            second = Path(raw) / "second"
            first.write_bytes(b"same")
            second.write_bytes(b"same")
            self.assertEqual(repeatability.sha256(first), repeatability.sha256(second))


if __name__ == "__main__":
    unittest.main()
