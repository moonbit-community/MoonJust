#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("generate_release_evidence.py")
SPEC = importlib.util.spec_from_file_location("moonjust_release_evidence", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evidence)


class ReleaseEvidenceTest(unittest.TestCase):
    def test_performance_report_accepts_complete_cold_warm_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "performance.json"
            workloads = {}
            for workload in ("project-modules", "project-parameters", "project-execution"):
                workloads[workload] = {
                    kind: {
                        condition: {"latency_samples": 3, "median_ms": 1.0}
                        for condition in ("cold", "warm")
                    }
                    for kind in ("official", "candidate-native", "candidate-wasm")
                }
            path.write_text(
                json.dumps(
                    {
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
                )
            )
            failures: list[str] = []
            summary = evidence.performance_summary(path, failures)
            self.assertEqual(summary["mode"], "report-only")
            self.assertEqual(failures, [])

    def test_performance_report_rejects_missing_cold_warm_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "performance.json"
            path.write_text(
                json.dumps(
                    {
                        "schema_version": 3,
                        "status": "passed",
                        "configuration": {"mode": "report-only"},
                        "machine": {"system": "Linux", "machine": "x86_64"},
                    }
                )
            )
            failures: list[str] = []
            evidence.performance_summary(path, failures)
            self.assertIn("performance benchmark is missing cold/warm evidence", failures)

    def test_coverage_summary_keeps_changed_and_package_rates_informational(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "coverage.json"
            path.write_text(
                json.dumps(
                    {
                        "overall": {"rate": 0.80},
                        "changed": {"valid": 100, "rate": 0.01},
                        "packages": {"parser": {"rate": 0.01}},
                    }
                )
            )
            failures: list[str] = []
            evidence.coverage_summary(path, failures)
            self.assertEqual(failures, [])

    def test_cloud_performance_requires_all_exact_head_platform_reports(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "performance.json"
            commit = "a" * 40
            workloads = {}
            for workload in ("project-modules", "project-parameters", "project-execution"):
                workloads[workload] = {
                    kind: {
                        condition: {"latency_samples": 3, "median_ms": 1.0}
                        for condition in ("cold", "warm")
                    }
                    for kind in ("official", "candidate-native", "candidate-wasm")
                }
            reports = {}
            for platform_name in evidence.REQUIRED_PLATFORMS:
                reports[platform_name] = {
                    "commit_sha": commit,
                    "report": {
                        "status": "passed",
                        "cold_warm": {
                            "enabled": True,
                            "rounds": 3,
                            "warmups_per_round": 5,
                            "workloads": workloads,
                        }
                    },
                }
            path.write_text(
                json.dumps(
                    {
                        "schema_version": 3,
                        "status": "passed",
                        "commit": commit,
                        "configuration": {"mode": "report-only"},
                        "platform_reports": reports,
                    }
                )
            )
            failures: list[str] = []
            summary = evidence.performance_summary(path, failures, commit)
            self.assertEqual(summary["mode"], "report-only")
            self.assertEqual(failures, [])

    def test_moon_toolchain_identity_ignores_install_paths(self) -> None:
        first = "moon 1 (abc) /home/runner/.moon/bin/moon\nmoonc 2 C:\\\\moon\\\\moonc"
        second = "moon 1 (abc) /Users/example/.moon/bin/moon\nmoonc 2 /opt/moon/moonc"
        self.assertEqual(
            evidence.moon_toolchain_identity(first),
            evidence.moon_toolchain_identity(second),
        )

    def test_toolchain_summary_rejects_cross_job_drift(self) -> None:
        failures: list[str] = []
        summary = evidence.toolchain_summary(
            {"native": {"toolchain": "moon 1"}, "wasm": {"toolchain": "moon 1"}},
            {"summary": {"moon": "moon 2 /tmp/moon"}},
            {},
            failures,
        )
        self.assertIsNone(summary["identity"])
        self.assertEqual(
            failures,
            ["infrastructure: MoonBit toolchain fingerprints differ across jobs"],
        )

    def test_assignment_parser_rejects_ambiguous_values(self) -> None:
        with self.assertRaisesRegex(ValueError, "NAME=PATH"):
            evidence.parse_assignment("linux-x86_64")

    def test_test_map_reports_unverified_compatibility_only(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "map.jsonl"
            rows = [
                {"scope": "compatibility", "disposition": "verified-contract"},
                {
                    "id": "JUST-1.57.0-0002",
                    "scope": "compatibility",
                    "disposition": "unverified",
                    "owner_area": "lexer",
                    "upstream_name": "lexer::tests::example",
                    "reason": "missing independent test",
                    "tracking": "MJ-CONTRACT-0002",
                },
                {"scope": "excluded-completion", "disposition": "excluded-completion"},
            ]
            path.write_text("".join(json.dumps(row) + "\n" for row in rows))
            failures: list[str] = []
            summary = evidence.test_map_summary(path, failures)
            self.assertEqual(summary["unverified"], 1)
            self.assertEqual(summary["incomplete_by_area"], {"lexer": 1})
            self.assertEqual(
                summary["incomplete_by_disposition"], {"unverified": 1}
            )
            self.assertEqual(
                summary["incomplete_registrations"][0]["id"],
                "JUST-1.57.0-0002",
            )
            self.assertEqual(
                failures,
                ["strict release evidence has 1 incomplete registrations (lexer=1)"],
            )

    def test_compatibility_summary_keeps_exclusions_out_of_denominator(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "compat.jsonl"
            rows = [
                {
                    "disposition": "exact",
                    "upstream_commit": evidence.UPSTREAM_COMMIT,
                    "compatibility_rate_denominator": True,
                },
                {
                    "disposition": "excluded-completion",
                    "upstream_commit": evidence.UPSTREAM_COMMIT,
                    "compatibility_rate_denominator": False,
                },
            ]
            path.write_text("".join(json.dumps(row) + "\n" for row in rows))
            failures: list[str] = []
            summary = evidence.compatibility_summary(path, failures)
            self.assertEqual(summary["denominator"], 1)
            self.assertEqual(failures, [])

    def test_platform_evidence_requires_exact_head_and_required_tasks(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            commit = "a" * 40
            paths: dict[str, Path] = {}
            for name, system in evidence.PLATFORM_SYSTEMS.items():
                tasks = [
                    {"name": "platform", "status": "passed"},
                    {"name": "wasm-platform", "status": "passed"},
                ]
                if name == "linux-x86_64":
                    tasks.append({"name": "official-harness", "status": "passed"})
                path = directory / f"{name}.json"
                path.write_text(
                    json.dumps(
                        {
                            "schema_version": 2,
                            "commit_sha": commit,
                            "mode": "compat",
                            "status": "passed",
                            "host": {"system": system},
                            "measurements": {"tasks": tasks},
                        }
                    )
                )
                paths[name] = path
            failures: list[str] = []
            summaries = evidence.platform_evidence_summaries(paths, commit, failures)
            self.assertEqual(set(summaries), evidence.REQUIRED_PLATFORMS)
            self.assertEqual(failures, [])

            windows = json.loads(paths["windows-x86_64"].read_text())
            windows["commit_sha"] = "b" * 40
            windows["measurements"]["tasks"][0]["status"] = "failed"
            paths["windows-x86_64"].write_text(json.dumps(windows))
            failures = []
            evidence.platform_evidence_summaries(paths, commit, failures)
            self.assertIn(
                "platform evidence commit differs for windows-x86_64", failures
            )
            self.assertIn(
                "platform evidence task platform is not passing for windows-x86_64",
                failures,
            )

    def test_official_harness_evidence_is_validated_separately(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "official.json"
            commit = "a" * 40
            path.write_text(
                json.dumps(
                    {
                        "schema_version": 2,
                        "commit_sha": commit,
                        "mode": "compat",
                        "status": "passed",
                        "host": {"system": "Linux"},
                        "measurements": {
                            "tasks": [
                                {"name": "official-harness", "status": "passed"}
                            ]
                        },
                    }
                )
            )
            failures: list[str] = []
            summary = evidence.official_harness_summary(path, commit, failures)
            self.assertEqual(summary["tasks"], {"official-harness": "passed"})
            self.assertEqual(failures, [])

    def test_contract_summary_requires_exact_unique_target_matrix(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            test_map = directory / "map.jsonl"
            results = directory / "results.jsonl"
            registration = {
                "id": "JUST-1.57.0-0001",
                "upstream_name": "config::tests::first",
                "upstream_source": {
                    "path": "src/config.rs",
                    "line": 1,
                    "file_sha256": "0" * 64,
                },
                "disposition": "verified-contract",
                "targets": ["native", "wasm1"],
            }
            test_map.write_text(json.dumps(registration) + "\n")
            execution = {
                "schema_version": 1,
                "case_id": registration["id"],
                "target": "native",
                "passed": True,
                "upstream_commit": evidence.UPSTREAM_COMMIT,
                "upstream_name": registration["upstream_name"],
                "upstream_source": registration["upstream_source"],
            }
            results.write_text(json.dumps(execution) + "\n" + json.dumps(execution) + "\n")
            failures: list[str] = []
            evidence.contract_summary(results, test_map, failures)
            self.assertIn(
                "contract results contain duplicate case/target executions",
                failures,
            )
            self.assertIn(
                "contract execution target matrix differs from the test map",
                failures,
            )

    def test_fatal_record_preserves_a_machine_readable_failure(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            output = Path(raw) / "evidence.json"
            previous = evidence.sys.argv
            evidence.sys.argv = ["generate_release_evidence.py", "--output", str(output)]
            try:
                evidence.write_fatal_record(ValueError("missing coverage"))
            finally:
                evidence.sys.argv = previous
            record = json.loads(output.read_text())
            self.assertEqual(record["status"], "failed")
            self.assertIn("missing coverage", record["failures"][0])

    def test_aggregate_preserves_partial_evidence_when_inputs_are_missing(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            output = Path(raw) / "evidence.json"
            missing = Path(raw) / "missing.json"
            previous = evidence.sys.argv
            evidence.sys.argv = [
                "generate_release_evidence.py",
                "--test-map",
                str(missing),
                "--contract-results",
                str(missing),
                "--coverage",
                str(missing),
                "--performance",
                str(missing),
                "--wasm",
                str(missing),
                "--output",
                str(output),
                "--strict",
            ]
            try:
                self.assertEqual(evidence.main(), 1)
            finally:
                evidence.sys.argv = previous
            record = json.loads(output.read_text())
            self.assertEqual(record["status"], "missing")
            self.assertTrue(record["missing_inputs"])
            self.assertIn("release evidence input is missing", " ".join(record["failures"]))

    def test_repeatability_hashes_must_match_release_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            directory = Path(raw)
            paths: dict[str, Path] = {}
            native = {}
            sizes = {}
            for name in evidence.REQUIRED_PLATFORMS:
                path = directory / f"{name}.json"
                path.write_text(
                    json.dumps(
                        {
                            "schema_version": 1,
                            "status": "passed",
                            "commit": "candidate",
                            "platform": name,
                            "pairs": {
                                "native": {"sha256": f"native-{name}"},
                                "archive": {"sha256": f"archive-{name}"},
                            },
                        }
                    )
                )
                paths[name] = path
                native[name] = {"sha256": f"native-{name}"}
                sizes[name] = {
                    "summary": {"archive": {"sha256": f"archive-{name}"}}
                }
            wasm_path = directory / "wasm1.json"
            wasm_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "status": "passed",
                        "commit": "candidate",
                        "platform": "wasm1",
                        "pairs": {"wasm1": {"sha256": "wasm-hash"}},
                    }
                )
            )
            paths["wasm1"] = wasm_path
            failures: list[str] = []
            evidence.repeatability_summaries(
                paths,
                "candidate",
                native,
                {"sha256": "wasm-hash"},
                sizes,
                failures,
            )
            self.assertEqual(failures, [])


if __name__ == "__main__":
    unittest.main()
