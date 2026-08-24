from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("aggregate_cloud.py")
SPEC = importlib.util.spec_from_file_location("moonjust_aggregate_cloud", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
cloud = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cloud)


def report(commit: str) -> dict[str, object]:
    workloads = {
        workload: {
            kind: {
                condition: {"latency_samples": 3, "median_ms": 1.0}
                for condition in ("cold", "warm")
            }
            for kind in cloud.REQUIRED_KINDS
        }
        for workload in cloud.REQUIRED_WORKLOADS
    }
    return {
        "schema_version": 2,
        "commit_sha": commit,
        "tree_sha": "tree",
        "host": {"system": "Linux"},
        "measurements": {
            "report": {
                "schema_version": 3,
                "status": "passed",
                "configuration": {"mode": "report-only"},
                "cold_warm": {
                    "enabled": True,
                    "rounds": 3,
                    "warmups_per_round": 5,
                    "workloads": workloads,
                },
            }
        },
    }


class AggregateCloudTest(unittest.TestCase):
    def test_aggregates_exact_head_and_keeps_source_status_as_observation(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            commit = "a" * 40
            paths = {}
            for name in cloud.REQUIRED_PLATFORMS:
                path = root / f"{name}.json"
                path.write_text(json.dumps(report(commit)))
                paths[name] = path
            output = root / "results.json"
            cloud.aggregate(paths, commit, output)
            value = json.loads(output.read_text())
            self.assertEqual(value["status"], "passed")
            self.assertEqual(value["configuration"]["mode"], "report-only")
            self.assertEqual(value["provenance"]["source_statuses"]["linux-x86_64"], "passed")

    def test_timing_values_are_observations_not_a_gate(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            commit = "a" * 40
            paths = {}
            for name in cloud.REQUIRED_PLATFORMS:
                value = report(commit)
                nested = value["measurements"]["report"]
                for workload in nested["cold_warm"]["workloads"].values():
                    for artifact in workload.values():
                        for summary in artifact.values():
                            summary["median_ms"] = 999999.0
                path = root / f"{name}.json"
                path.write_text(json.dumps(value))
                paths[name] = path
            output = root / "results.json"
            cloud.aggregate(paths, commit, output)
            self.assertEqual(json.loads(output.read_text())["status"], "passed")

    def test_rejects_mixed_exact_heads(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            paths = {}
            for index, name in enumerate(sorted(cloud.REQUIRED_PLATFORMS)):
                path = root / f"{name}.json"
                path.write_text(json.dumps(report(("a" if index else "b") * 40)))
                paths[name] = path
            with self.assertRaisesRegex(ValueError, "differs from exact head"):
                cloud.aggregate(paths, "a" * 40, root / "results.json")


if __name__ == "__main__":
    unittest.main()
