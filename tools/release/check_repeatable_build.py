#!/usr/bin/env python3
"""Verify cache-disabled Native and wasm builds are byte-identical."""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import tempfile


def build(repo: pathlib.Path, target: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path]:
    environment = {
        **os.environ,
        "MOON_DEP_CACHE": "off",
        "MOON_BUILD_CACHE": "off",
        "SOURCE_DATE_EPOCH": "0",
        "ZERO_AR_DATE": "1",
    }
    subprocess.run(
        ["moon", "build", "--frozen", "--release", "--strip", "--target", "native", "--target-dir", str(target), "cmd/just"],
        cwd=repo,
        check=True,
        env=environment,
    )
    subprocess.run(
        ["moon", "build", "--frozen", "--release", "--strip", "--target", "wasm", "--target-dir", str(target), "cmd/just"],
        cwd=repo,
        check=True,
        env=environment,
    )
    native = target / "native/release/build/cmd/just/just.exe"
    wasm = target / "wasm/release/build/cmd/just/just.wasm"
    if not native.is_file() or not wasm.is_file():
        raise SystemExit("repeatability artifact is missing")
    return native, wasm


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    repo = args.repo.resolve()
    with tempfile.TemporaryDirectory(prefix="moonjust-repeatable-") as raw:
        root = pathlib.Path(raw)
        target = root / "build"
        first_native, first_wasm = build(repo, target)
        first_native_bytes = first_native.read_bytes()
        first_wasm_bytes = first_wasm.read_bytes()
        shutil.rmtree(target)
        second_native, second_wasm = build(repo, target)
        if first_native_bytes != second_native.read_bytes():
            raise SystemExit("two clean Native builds from the same path differ")
        if first_wasm_bytes != second_wasm.read_bytes():
            raise SystemExit("two clean wasm builds from the same path differ")
    print("Release repeatability verified: two cache-disabled clean Native/wasm builds are byte-identical")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
