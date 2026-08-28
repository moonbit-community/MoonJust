#!/usr/bin/env python3
"""Build the reproducible release wasm1 artifact and optimize it post-link."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

import optimize_wasm


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--target-dir", type=Path)
    parser.add_argument("--wasm-opt", type=Path)
    args = parser.parse_args()
    repo = args.repo.resolve()
    target_dir = args.target_dir or repo / "_build"
    if not target_dir.is_absolute():
        target_dir = repo / target_dir
    target_dir = target_dir.resolve()
    raw_target_dir = target_dir / ".moonjust-wasm-raw"
    environment = os.environ.copy()
    environment.setdefault("SOURCE_DATE_EPOCH", "0")
    environment.setdefault("ZERO_AR_DATE", "1")
    subprocess.run(
        [
            "moon",
            "build",
            "--frozen",
            "--release",
            "--strip",
            "--target",
            "wasm",
            "--target-dir",
            str(raw_target_dir),
            "cmd/just",
        ],
        cwd=repo,
        check=True,
        env=environment,
    )
    raw_artifact = raw_target_dir / "wasm/release/build/cmd/just/just.wasm"
    artifact = target_dir / "wasm/release/build/cmd/just/just.wasm"
    optimize_wasm.optimize(
        raw_artifact,
        artifact,
        cache=repo / "_build/tooling/binaryen",
        wasm_opt=args.wasm_opt,
    )
    print(artifact)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(f"wasm release build error: {error}")
