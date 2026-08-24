#!/usr/bin/env python3
"""Compatibility bridge for checks whose detailed fixtures are still shell-owned.

The bridge is intentionally Unix-only and is not reachable from the Windows
CI matrix. It exists while the individual fixture-heavy checks are being
converted; all workflow orchestration and portable checks use Python.
"""

from __future__ import annotations

import platform
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: legacy.py CHECK")
    if platform.system() == "Windows":
        raise SystemExit(f"{sys.argv[1]} is not enabled on Windows in this transition")
    repo = Path(__file__).resolve().parents[3]
    script = repo / "tools/verification/checks" / f"{sys.argv[1]}.sh"
    return subprocess.run(["sh", str(script)], cwd=repo, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
