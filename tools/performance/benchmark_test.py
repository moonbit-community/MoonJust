#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).with_name("benchmark.py")
SPEC = importlib.util.spec_from_file_location("moonjust_benchmark", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


class BenchmarkTest(unittest.TestCase):
    def test_balanced_orders_are_deterministic_and_position_balanced(self) -> None:
        first = benchmark.balanced_orders(("a", "b", "c"), 30, 1570)
        second = benchmark.balanced_orders(("a", "b", "c"), 30, 1570)
        self.assertEqual(first, second)
        for position in range(3):
            self.assertEqual(
                Counter(order[position] for order in first),
                {"a": 10, "b": 10, "c": 10},
            )

    def test_fixture_inventory_and_hashes_are_stable(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            fixtures = benchmark.write_fixtures(Path(raw))
            self.assertEqual(
                list(fixtures),
                [
                    "startup",
                    "recipes-10",
                    "recipes-100",
                    "recipes-1000",
                    "recipes-5000",
                    "check",
                    "format",
                    "dag-1000",
                    "noops-100",
                    "project-modules",
                    "project-parameters",
                    "project-execution",
                ],
            )
            self.assertEqual(fixtures["recipes-1000"][0].stat().st_size, 7000)
            self.assertNotIn(b"\r", fixtures["recipes-1000"][0].read_bytes())
            self.assertEqual(fixtures["dag-1000"][0].read_text().count("node"), 1998)
            self.assertEqual(benchmark.fixture_profile("project-modules"), "real-project")
            self.assertEqual(len(benchmark.fixture_files("project-modules", fixtures["project-modules"][0])), 2)

    def test_cold_warm_phase_records_three_conditions_per_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            commands = {"a": ["a"], "b": ["b"]}
            rows: list[dict[str, object]] = []
            with mock.patch.object(benchmark, "run_latency_sample", return_value=1.0) as sample:
                values, duration = benchmark.collect_cold_warm_phase(
                    "project-test", commands, root, 1570, rows, "moon", {"a": "a", "b": "b"}
                )
            self.assertGreaterEqual(duration, 0.0)
            self.assertEqual(len(rows), 12)
            self.assertEqual([len(values[k][c]) for k in values for c in ("cold", "warm")], [3] * 4)
            self.assertEqual({row["condition"] for row in rows}, {"cold", "warm"})
            self.assertEqual(
                [row["condition"] for row in rows[:4]],
                ["cold", "warm", "cold", "warm"],
            )
            self.assertEqual(sample.call_count, 3 * (2 + 5 * 2 + 2))

    def test_summary_keeps_latency_and_memory_separate(self) -> None:
        summary = benchmark.summarize([1.0, 2.0, 3.0], [10, None, 20])
        self.assertEqual(summary["median_ms"], 2.0)
        self.assertEqual(summary["p95_ms"], 3.0)
        self.assertEqual(summary["peak_rss_kib"], 20)
        self.assertEqual(summary["latency_samples"], 3)
        self.assertEqual(summary["memory_samples"], 3)
        self.assertEqual(summary["memory_observations"], 2)
        self.assertIsNotNone(summary["rss_cv"])

    def test_summary_marks_missing_rss_observations(self) -> None:
        summary = benchmark.summarize([1.0, 1.1], [None, None])
        self.assertEqual(summary["memory_observations"], 0)
        self.assertIsNone(summary["rss_cv"])

    def test_stability_policy_requires_three_stable_windows(self) -> None:
        self.assertTrue(benchmark.stable_window([100.0] * 5))
        self.assertFalse(benchmark.stable_window([90.0, 100.0, 110.0, 100.0, 100.0]))

    def test_evidence_reader_migrates_legacy_schema(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "legacy.json"
            path.write_text('{"schema_version": 2, "status": "passed"}\n')
            value = benchmark.read_evidence(path)
            self.assertEqual(value["schema_version"], 4)
            self.assertEqual(value["legacy_schema_version"], 2)

    def test_shadow_result_sets_ignore_measurement_values(self) -> None:
        fixtures = {"fixtures": {"startup": {"commands": {"native": ["just", "--justfile", "/tmp/moonjust-benchmark-old/input.just"]}}}}
        changed = {"fixtures": {"startup": {"commands": {"native": ["just", "--justfile", "/tmp/moonjust-benchmark-new/input.just"]}}}}
        changed["workloads"] = {"startup": {"native": {"median_ms": 999}}}
        self.assertTrue(benchmark.shadow_result_sets_match(fixtures, changed))

    def test_unsupported_memory_sampler_skips_command(self) -> None:
        with mock.patch.object(benchmark, "memory_supported", return_value=False):
            with mock.patch.object(benchmark.subprocess, "run") as run:
                self.assertIsNone(benchmark.run_memory_sample(["unused"], Path(".")))
                run.assert_not_called()

    def test_cpu_list_parser_handles_ranges(self) -> None:
        self.assertEqual(benchmark.parse_cpu_list("1-3,7,9-10"), {1, 2, 3, 7, 9, 10})

    def test_cpuinfo_field_reads_colon_delimited_values(self) -> None:
        value = "model name\t: Example CPU\nmicrocode\t: 0x123\n"
        self.assertEqual(benchmark.cpuinfo_field(value, "model name"), "Example CPU")
        self.assertEqual(benchmark.cpuinfo_field(value, "microcode"), "0x123")

    def test_benchmark_environment_describes_windows_portable_host(self) -> None:
        with (
            mock.patch.object(benchmark.platform, "system", return_value="Windows"),
            mock.patch.object(benchmark.platform, "machine", return_value="AMD64"),
        ):
            environment = benchmark.benchmark_environment()
        self.assertEqual(environment["MOONJUST_OS"], "windows")
        self.assertEqual(environment["MOONJUST_ARCH"], "amd64")

    def test_collect_phase_trace_parses_only_the_trace_record(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            command = [
                sys.executable,
                "-c",
                "import sys; print('MOONJUST_PERF_TRACE {\"events\":[{\"stage\":\"application.plan\",\"elapsed_ms\":3}]}', file=sys.stderr)",
            ]
            value = benchmark.collect_phase_trace(command, root)
            self.assertEqual(
                value,
                {"events": [{"stage": "application.plan", "elapsed_ms": 3}]},
            )

    def test_collect_phase_trace_merges_detail_events(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            script = (
                "import sys; "
                "print('MOONJUST_PERF_DETAIL {\"events\":[{\"stage\":\"run.load\",\"elapsed_ms\":2}]}', file=sys.stderr); "
                "print('MOONJUST_PERF_TRACE {\"events\":[{\"stage\":\"application.plan\",\"elapsed_ms\":3}]}', file=sys.stderr)"
            )
            value = benchmark.collect_phase_trace(
                [sys.executable, "-c", script], root
            )
            self.assertEqual(
                value,
                {
                    "events": [
                        {"stage": "application.plan", "elapsed_ms": 3}
                    ],
                    "detail_events": [
                        {"stage": "run.load", "elapsed_ms": 2}
                    ],
                },
            )

    def test_collect_phase_trace_returns_none_for_static_output(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            value = benchmark.collect_phase_trace(
                [sys.executable, "-c", "print('version')"], Path(raw)
            )
            self.assertIsNone(value)

    def test_collect_phase_trace_keeps_probe_failures_out_of_latency_gate(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            value = benchmark.collect_phase_trace(
                [sys.executable, "-c", "import sys; print('probe failed', file=sys.stderr); sys.exit(3)"],
                Path(raw),
            )
            self.assertEqual(value["error"], "trace command failed with exit code 3")
            self.assertIn("probe failed", value["stderr_tail"])


if __name__ == "__main__":
    unittest.main()
