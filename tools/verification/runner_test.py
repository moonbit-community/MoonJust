#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("runner.py")
SPEC = importlib.util.spec_from_file_location("moonjust_runner", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class RunnerTest(unittest.TestCase):
    def test_modes_are_layered_and_deterministic(self) -> None:
        self.assertEqual(runner.mode_commands("fast")[0], ("moon", "fmt", "--check"))
        self.assertLess(len(runner.mode_commands("fast")), len(runner.mode_commands("verify")))
        self.assertEqual(runner.mode_commands("verify"), runner.mode_commands("verify"))
        self.assertIn(("./tools/checks/compatibility.sh",), runner.mode_commands("compat"))

    def test_build_registry_claims_a_key_once(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            registry = runner.BuildRegistry(Path(raw))
            first = registry.claim("abc", "native", "release")
            second = registry.claim("abc", "native", "release")
            self.assertEqual(first[0], second[0])
            self.assertTrue(first[1])
            self.assertFalse(second[1])
            self.assertEqual(len(list(Path(raw).glob("*.json"))), 1)


if __name__ == "__main__":
    unittest.main()
