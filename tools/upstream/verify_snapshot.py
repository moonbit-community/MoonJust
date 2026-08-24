#!/usr/bin/env python3
"""Verify the pinned upstream snapshot without a shell dependency."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    subprocess.run([sys.executable, "tools/upstream/test_map.py"], cwd=repo, check=True)
    subprocess.run([sys.executable, "tools/upstream/verify_manifest.py"], cwd=repo, check=True)
    print("compatibility snapshot verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
