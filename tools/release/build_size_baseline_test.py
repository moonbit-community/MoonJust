#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("build_size_baseline.py")
SPEC = importlib.util.spec_from_file_location("moonjust_size_baseline", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
size_baseline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(size_baseline)


class BuildSizeBaselineTest(unittest.TestCase):
    def test_run_preserves_stdout_and_stderr_on_failure(self) -> None:
        with self.assertRaisesRegex(
            RuntimeError,
            r"(?s)command failed \(7\):.*stdout:\s+baseline-out.*stderr:\s+baseline-err",
        ):
            size_baseline.run(
                [
                    sys.executable,
                    "-c",
                    "import sys; print('baseline-out'); "
                    "print('baseline-err', file=sys.stderr); sys.exit(7)",
                ],
            )

    def test_archive_staging_is_repeatable(self) -> None:
        with tempfile.TemporaryDirectory(prefix="moonjust-size-test-") as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            for name, contents in {
                "LICENSE": "license\n",
                "NOTICE": "notice\n",
                "README.mbt.md": "readme\n",
                "SECURITY.md": "security\n",
                "CHANGELOG.md": "change\n",
            }.items():
                (source / name).write_text(contents, encoding="utf-8")
            native = source / "just"
            native.write_bytes(b"native")
            first = root / "first.tar.gz"
            second = root / "second.tar.gz"
            repo = Path(__file__).parents[2]
            size_baseline.stage_archive(repo, source, native, "linux-x86_64", first)
            size_baseline.stage_archive(repo, source, native, "linux-x86_64", second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(size_baseline.sha256(first), size_baseline.sha256(second))


if __name__ == "__main__":
    unittest.main()
