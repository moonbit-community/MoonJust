#!/usr/bin/env python3
"""Run one MoonBit test target and require a non-empty passing test suite."""

from __future__ import annotations

import re
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"native", "wasm"}:
        raise SystemExit("usage: test_target.py native|wasm")
    target = sys.argv[1]
    result = subprocess.run(
        ["moon", "test", "--target", target],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    output = result.stdout + result.stderr
    print(output, end="")
    if result.returncode != 0:
        return result.returncode
    if re.search(r"Total tests: [1-9][0-9]*, passed: [0-9]+, failed: 0\.", output) is None:
        print(f"test-count gate: no passing tests were observed for target {target}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
