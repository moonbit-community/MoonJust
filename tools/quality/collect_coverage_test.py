#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("collect_coverage.py")
SPEC = importlib.util.spec_from_file_location("moonjust_collect_coverage", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
coverage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(coverage)


class CollectCoverageTest(unittest.TestCase):
    def test_trace_and_source_discovery_is_sorted_and_target_scoped(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            repo = Path(raw)
            (repo / "_build").mkdir()
            (repo / "_build" / "moonbit_coverage_b").write_bytes(b"b")
            (repo / "_build" / "moonbit_coverage_a").write_bytes(b"a")
            source_root = repo / "_build" / "native" / "debug" / "test" / "pkg"
            source_root.mkdir(parents=True)
            (source_root / "z.trace.source").write_text("z")
            (source_root / "a.trace.source").write_text("a")
            wasm_root = repo / "_build" / "wasm" / "debug" / "test" / "pkg"
            wasm_root.mkdir(parents=True)
            (wasm_root / "wasm.trace.source").write_text("w")

            self.assertEqual(
                [path.name for path in coverage.trace_files(repo)],
                ["moonbit_coverage_a", "moonbit_coverage_b"],
            )
            self.assertEqual(
                [path.name for path in coverage.source_files(repo, "native")],
                ["a.trace.source", "z.trace.source"],
            )
            self.assertEqual(
                [path.name for path in coverage.source_files(repo, "wasm")],
                ["wasm.trace.source"],
            )


if __name__ == "__main__":
    unittest.main()
