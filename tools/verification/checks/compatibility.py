#!/usr/bin/env python3
"""Validate the pinned compatibility maps through Python entrypoints."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo = Path(__file__).resolve().parents[3]
    commands = [
        [sys.executable, "tools/upstream/test_map.py"],
        [sys.executable, "tools/upstream/verify_manifest.py"],
    ]
    for command in commands:
        subprocess.run(command, cwd=repo, check=True)
    print("compatibility snapshot verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
