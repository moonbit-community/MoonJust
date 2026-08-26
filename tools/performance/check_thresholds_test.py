from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("check_thresholds.py")
SPEC = importlib.util.spec_from_file_location("moonjust_check_thresholds", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def report(native: float = 1.0, wasm: float = 2.0) -> dict[str, object]:
    workloads = {}
    for workload in gate.WORKLOADS:
        workloads[workload] = {
            "official": {
                "median_ms": 10.0,
                "p95_ms": 12.0,
                "latency_samples": 15,
            },
            "candidate-native": {
                "median_ms": 10.0 * native,
                "p95_ms": 12.0 * native,
                "latency_samples": 15,
            },
            "candidate-wasm": {
                "median_ms": 10.0 * wasm,
                "p95_ms": 12.0 * wasm,
                "latency_samples": 15,
            },
        }
    return {
        "schema_version": 2,
        "commit_sha": "candidate",
        "tree_sha": "tree",
        "toolchain": "moon 0.1.20260824 / moonc 0.10.10 / moonrun 0.1.20260824",
        "measurements": {
            "report": {"status": "passed", "workloads": workloads}
        },
    }


class ThresholdGateTest(unittest.TestCase):
    def write_report(self, root: Path, name: str, value: dict[str, object]) -> Path:
        path = root / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def assignments(self, paths: dict[str, list[Path]]) -> dict[str, list[Path]]:
        return paths

    def test_strict_requires_three_batches_and_records_batch_ratios(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            paths = {
                platform: [self.write_report(root, f"{platform}-{index}.json", report()) for index in range(3)]
                for platform in gate.PLATFORMS
            }
            result = gate.check(paths, "strict", root / "performance-gate.json")
            self.assertEqual(result["status"], "passed")
            self.assertEqual(result["platforms"]["linux-x86_64"]["batch_count"], 3)
            self.assertEqual(
                result["platforms"]["linux-x86_64"]["workloads"]["startup"]["wasm"]["median_ratio"],
                2.0,
            )

    def test_strict_rejects_native_and_wasm_thresholds(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            paths = {
                platform: [
                    self.write_report(root, f"{platform}-{index}.json", report(native=1.2, wasm=3.2))
                    for index in range(3)
                ]
                for platform in gate.PLATFORMS
            }
            result = gate.check(paths, "strict", root / "performance-gate.json")
            self.assertEqual(result["status"], "failed")
            self.assertTrue(any("native" in failure for failure in result["failures"]))
            self.assertTrue(any("wasm" in failure for failure in result["failures"]))

    def test_pr_compares_against_accepted_baseline_with_five_percent_budget(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            paths = {
                platform: [self.write_report(root, f"{platform}.json", report(native=1.04, wasm=2.04))]
                for platform in gate.PLATFORMS
            }
            baseline = {
                "schema_version": 1,
                "source": {
                    "commit_sha": "8ae279fef0e3f445b19c57c24f34aa921165f1cb",
                    "official_commit": gate.OFFICIAL_COMMIT,
                    "toolchain": "moon 0.1.20260824 / moonc 0.10.10 / moonrun 0.1.20260824",
                },
                "platforms": {
                    platform: {
                        workload: {
                            "native_median": 1.0,
                            "native_p95": 1.0,
                            "wasm_median": 2.0,
                            "wasm_p95": 2.0,
                        }
                        for workload in gate.WORKLOADS
                    }
                    for platform in gate.PLATFORMS
                },
            }
            baseline_path = root / "baseline.json"
            baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
            result = gate.check(
                paths,
                "pr",
                root / "performance-gate.json",
                baseline_path,
            )
            self.assertEqual(result["status"], "passed")

    def test_pr_rejects_toolchain_mismatch_with_accepted_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            paths = {
                platform: [self.write_report(root, f"{platform}.json", report())]
                for platform in gate.PLATFORMS
            }
            paths["linux-x86_64"][0].write_text(
                json.dumps({**report(), "toolchain": "moon 0.1.20260819 / moonc 0.10.9 / moonrun 0.1.20260819"}),
                encoding="utf-8",
            )
            baseline = {
                "schema_version": 1,
                "source": {
                    "commit_sha": "8ae279fef0e3f445b19c57c24f34aa921165f1cb",
                    "official_commit": gate.OFFICIAL_COMMIT,
                    "toolchain": "moon 0.1.20260824 / moonc 0.10.10 / moonrun 0.1.20260824",
                },
                "platforms": {
                    platform: {
                        workload: {
                            "native_median": 1.0,
                            "native_p95": 1.0,
                            "wasm_median": 2.0,
                            "wasm_p95": 2.0,
                        }
                        for workload in gate.WORKLOADS
                    }
                    for platform in gate.PLATFORMS
                },
            }
            baseline_path = root / "baseline.json"
            baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
            result = gate.check(paths, "pr", root / "performance-gate.json", baseline_path)
            self.assertEqual(result["status"], "failed")
            self.assertTrue(any("toolchain differs" in failure for failure in result["failures"]))

    def test_wasm_relaxation_requires_three_batch_lower_bound_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            paths = {
                platform: [
                    self.write_report(root, f"{platform}-{index}.json", report(wasm=4.5))
                    for index in range(3)
                ]
                for platform in gate.PLATFORMS
            }
            evidence = {
                "schema_version": 1,
                "confidence": "95%",
                "workloads": {
                    f"{platform}/{workload}": {
                        "batches": 3,
                        "runtime_plus_package_lower_bound_ratio": 4.0,
                    }
                    for platform in gate.PLATFORMS
                    for workload in gate.WORKLOADS
                    if workload != "startup"
                },
            }
            evidence_path = root / "wasm-lower-bound.json"
            evidence_path.write_text(json.dumps(evidence), encoding="utf-8")
            result = gate.check(
                paths,
                "strict",
                root / "performance-gate.json",
                lower_bound=evidence_path,
            )
            self.assertEqual(result["status"], "failed")
            self.assertTrue(any("startup/wasm" in failure for failure in result["failures"]))

    def test_missing_batch_writes_diagnostic_gate_record(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            paths = {
                platform: [self.write_report(root, f"{platform}.json", report())]
                for platform in gate.PLATFORMS
            }
            paths["windows-x86_64"] = []
            result = gate.check(paths, "strict", root / "performance-gate.json")
            self.assertEqual(result["status"], "failed")
            self.assertEqual(result["platforms"]["windows-x86_64"]["batch_count"], 0)
            self.assertTrue((root / "performance-gate.json").is_file())
            self.assertTrue(any("windows-x86_64 has 0 batch" in failure for failure in result["failures"]))


if __name__ == "__main__":
    unittest.main()
