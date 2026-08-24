#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("merge_coverage.py")
SPEC = importlib.util.spec_from_file_location("moonjust_merge_coverage", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
merge_coverage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(merge_coverage)


class ChangedLinesTests(unittest.TestCase):
    def git(self, repo: Path, *args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=repo,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def write(self, repo: Path, relative: str, contents: str) -> None:
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def commit(self, repo: Path, message: str) -> str:
        self.git(repo, "add", ".")
        self.git(repo, "commit", "-m", message)
        return self.git(repo, "rev-parse", "HEAD")

    def test_frozen_baseline_compares_trees_when_not_ancestor(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            self.git(repo, "init", "-b", "main")
            self.git(repo, "config", "user.email", "moonjust@example.invalid")
            self.git(repo, "config", "user.name", "MoonJust Test")
            self.write(repo, "src/demo/core.mbt", "root\n")
            root = self.commit(repo, "root")

            self.git(repo, "switch", "-c", "frozen")
            self.write(repo, "src/demo/frozen.mbt", "shared\n")
            frozen = self.commit(repo, "frozen baseline")

            self.git(repo, "switch", "main")
            self.write(repo, "src/demo/frozen.mbt", "shared\n")
            self.write(repo, "src/demo/core.mbt", "root\nchanged\n")
            self.commit(repo, "squashed candidate")

            self.assertEqual(self.git(repo, "merge-base", frozen, "HEAD"), root)
            self.assertEqual(
                merge_coverage.changed_lines(repo, frozen),
                {"src/demo/core.mbt": {2}},
            )


if __name__ == "__main__":
    unittest.main()
