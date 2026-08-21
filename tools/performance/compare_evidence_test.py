#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("compare_evidence.py")
SPEC = importlib.util.spec_from_file_location("moonjust_compare_evidence", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
compare_evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(compare_evidence)


def write_fixture(root: Path, name: str, schema: int, command_path: Path) -> Path:
    raw = root / f"{name}.jsonl"
    raw.write_text(json.dumps({"phase": "latency", "exit_code": 0, "elapsed_ms": 1.0}) + "\n")
    evidence = root / f"{name}.json"
    evidence.write_text(
        json.dumps(
            {
                "schema_version": schema,
                "fixtures": {"startup": {"commands": {"candidate-native": ["just", "--justfile", str(command_path)]}}},
                "workloads": {"startup": {"candidate-native": {"median_ms": 1.0}}},
                "raw_samples": {"path": str(raw)},
            }
        )
    )
    return evidence


class CompareEvidenceTest(unittest.TestCase):
    def test_schema_migration_and_fixture_paths_compare(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            legacy = write_fixture(root, "legacy", 2, root / "moonjust-benchmark-old" / "input.just")
            current = write_fixture(root, "current", 3, root / "moonjust-benchmark-new" / "input.just")
            result = compare_evidence.compare(legacy, current)
            self.assertEqual(result["status"], "passed")
            self.assertEqual(result["inventories"]["legacy_commands"], 1)

    def test_command_inventory_difference_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            legacy = write_fixture(root, "legacy", 2, root / "old.just")
            current = write_fixture(root, "current", 3, root / "new.just")
            result = compare_evidence.compare(legacy, current)
            self.assertEqual(result["status"], "failed")
            self.assertTrue(result["mismatches"])


if __name__ == "__main__":
    unittest.main()
