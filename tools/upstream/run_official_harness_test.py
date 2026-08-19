#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
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


if __name__ == "__main__":
    unittest.main()
