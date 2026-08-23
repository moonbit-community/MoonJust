#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("freeze_artifact_baseline.py")
SPEC = importlib.util.spec_from_file_location("moonjust_freeze_size", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
freeze = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(freeze)


class FreezeArtifactBaselineTest(unittest.TestCase):
    def test_repeated_value_rejects_non_determinism(self) -> None:
        reports = [{"native": {"bytes": 1}}, {"native": {"bytes": 2}}]
        with self.assertRaisesRegex(ValueError, "repeat builds differ"):
            freeze.repeated_value(reports, "native", "bytes")

    def test_repeated_value_returns_identical_value(self) -> None:
        reports = [{"native": {"sha256": "abc"}}, {"native": {"sha256": "abc"}}]
        self.assertEqual(freeze.repeated_value(reports, "native", "sha256"), "abc")

    def test_repeated_json_value_returns_equal_sections(self) -> None:
        reports = [
            {"native": {"sections": [{"name": ".text", "bytes": 1}]}},
            {"native": {"sections": [{"name": ".text", "bytes": 1}]}},
        ]
        self.assertEqual(
            freeze.repeated_json_value(reports, "native", "sections"),
            [{"name": ".text", "bytes": 1}],
        )


if __name__ == "__main__":
    unittest.main()
