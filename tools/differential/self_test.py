#!/usr/bin/env python3
"""Validate the differential harness's self-test contract portably."""

from __future__ import annotations

import tempfile
from pathlib import Path


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="moonjust-diff-self-test-") as raw:
        root = Path(raw)
        cases = root / "cases.toml"
        cases.write_text(
            "schema_version = 3\nupstream = 'self-test'\n\n"
            "[[case]]\nid = 'MJ-COMPAT-SELF-MATCH'\n"
            "directory = '01-match'\nowner_area = 'differential-harness'\n"
            "status = 'match'\ncompare = ['status', 'stdout', 'stderr', 'tree']\nupstream_tests = []\n",
            encoding="utf-8",
        )
        if "MJ-COMPAT-SELF-MATCH" not in cases.read_text(encoding="utf-8"):
            raise SystemExit("differential self-test fixture was not written")
    print("differential self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
