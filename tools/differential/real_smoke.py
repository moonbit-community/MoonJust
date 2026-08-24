#!/usr/bin/env python3
"""Run the real differential smoke through the Python harness."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    oracle = Path(os.environ.get("MOONJUST_ORACLE_CANDIDATE", str(repo / "_build/upstream/just-1.57.0/target/release/just.exe")))
    native = Path(os.environ.get("MOONJUST_NATIVE_CANDIDATE", str(repo / "_build/native/debug/build/cmd/just/just.exe")))
    wasm = Path(os.environ.get("MOONJUST_WASM_CANDIDATE", str(repo / "_build/wasm/debug/build/cmd/just/just.wasm")))
    if not oracle.is_file() or not native.is_file() or not wasm.is_file():
        raise SystemExit("differential smoke artifacts are incomplete")
    subprocess.run(
        [sys.executable, "tools/differential/run.py", "--upstream", str(oracle),
         "--candidate-native", str(native), "--candidate-wasm", str(wasm),
         "--wasm-policy", str(repo / "policies/execute.toml"),
         "--artifacts", str(repo / "_build/differential/real")],
        cwd=repo,
        check=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
