#!/usr/bin/env python3
"""Run MoonBit's package benchmark stages without a shell wrapper."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", nargs="?", default="native", choices=("native", "wasm"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    return subprocess.run(
        ["moon", "bench", "--frozen", "--release", "--target", args.target, "--no-parallelize",
         "src/lexer", "src/parser", "src/semantic", "src/formatter", "src/evaluator", "src/executor"],
        cwd=repo,
        check=False,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
