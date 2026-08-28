#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("run_official_harness.py")
SPEC = importlib.util.spec_from_file_location("moonjust_official_harness", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
harness = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(harness)


class OfficialHarnessTest(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Unix process groups are not available")
    def test_isolated_timeout_kills_the_process_group(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            result, timed_out = harness.run_isolated_unix(
                [sys.executable, "-c", "import time; time.sleep(10)"],
                cwd=Path(raw),
                timeout=0.05,
            )
        self.assertTrue(timed_out)
        self.assertEqual(result.returncode, 124)

    @unittest.skipIf(os.name == "nt", "Unix signal masks are not available")
    def test_isolated_runner_restores_ignored_parent_signal(self) -> None:
        previous = harness.signal.signal(harness.signal.SIGHUP, harness.signal.SIG_IGN)
        try:
            result, timed_out = harness.run_isolated_unix(
                [
                    sys.executable,
                    "-c",
                    "import signal; print(signal.getsignal(signal.SIGHUP))",
                ],
                cwd=Path(tempfile.gettempdir()),
                timeout=1,
            )
        finally:
            harness.signal.signal(harness.signal.SIGHUP, previous)
        self.assertFalse(timed_out)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "0")

    @unittest.skipIf(os.name == "nt", "Unix process groups are not available")
    def test_isolated_runner_merges_signal_marker_environment(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            result, timed_out = harness.run_isolated_unix(
                [
                    sys.executable,
                    "-c",
                    "import os; print(os.environ['MOONJUST_SIGNAL_RUN_ID'])",
                ],
                cwd=Path(raw),
                timeout=1,
                extra_env={"MOONJUST_SIGNAL_RUN_ID": "test-marker"},
            )
        self.assertFalse(timed_out)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "test-marker")

    def test_timeout_snapshot_identifies_orphaned_signal_request(self) -> None:
        snapshot = """\n[timeout process snapshot]\n  123   1   123   123 S /tmp/just --request \"signal\"\n  456 123   123   123 S /bin/sh -c sleep 1\n"""
        self.assertEqual(harness.timeout_snapshot_orphans(snapshot), [123])

    def test_oracle_host_requires_one_nonempty_host(self) -> None:
        encoded = '{"host":"windows-amd64","schema_version":4}\n'
        self.assertEqual(harness.oracle_host(encoded, "oracle"), "windows-amd64")
        with self.assertRaises(RuntimeError):
            harness.oracle_host(
                '{"host":"darwin-arm64","schema_version":4}\n'
                '{"host":"windows-amd64","schema_version":4}\n',
                "oracle",
            )

    def test_oracle_comparison_rejects_cross_platform_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "results.jsonl"
            path.write_text(
                '{"host":"darwin-arm64","schema_version":4}\n',
                encoding="utf-8",
            )
            with self.assertRaises(RuntimeError):
                harness.verify_audited_oracle(
                    path,
                    '{"host":"windows-amd64","schema_version":4}\n',
                )

    def test_wasm_nonunicode_host_limitation_is_narrow(self) -> None:
        self.assertTrue(
            harness.is_wasm_nonunicode_host_limitation(
                "panicked at /rustc/src/std/src/env.rs:162:83: called unwrap: foo\\xff"
            )
        )
        self.assertTrue(
            harness.is_wasm_nonunicode_host_limitation(
                "panicked at crates/moonrun/src/filesystem/mod.rs:176:14: "
                "called `Option::unwrap()` on a `None` value"
            )
        )
        self.assertFalse(
            harness.is_wasm_nonunicode_host_limitation(
                "error: host error while loading"
            )
        )
        self.assertFalse(
            harness.is_wasm_nonunicode_host_limitation(
                "called `Option::unwrap()` on a `None` value"
            )
        )

    def test_platform_host_cases_are_explicit(self) -> None:
        self.assertEqual(
            harness.PLATFORM_HOST_CASES,
            {
                "non_unicode::warn_for_non_unicode_invocation_directory",
                "non_unicode::warn_for_non_unicode_justfile_path",
            },
        )

    def test_default_results_path_is_host_specific(self) -> None:
        with mock.patch.object(harness.platform, "system", return_value="Darwin"):
            self.assertEqual(
                harness.default_results_path(Path("/repo")).name,
                "harness-results.jsonl",
            )
        with mock.patch.object(harness.platform, "system", return_value="Linux"):
            self.assertEqual(
                harness.default_results_path(Path("/repo")).name,
                "harness-results-linux.jsonl",
            )
        with mock.patch.object(harness.platform, "system", return_value="Windows"):
            self.assertEqual(
                harness.default_results_path(Path("/repo")).name,
                "harness-results-windows.jsonl",
            )


if __name__ == "__main__":
    unittest.main()
