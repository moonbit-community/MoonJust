#!/usr/bin/env python3
"""Rebuild and smoke-test a published source package without build caches."""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile


def version(manifest: pathlib.Path) -> str:
    match = re.search(r'^version = "([^"]+)"$', manifest.read_text(), re.M)
    if match is None:
        raise SystemExit("source package version is missing")
    return match.group(1)


def extract(archive: pathlib.Path, target: pathlib.Path) -> None:
    with zipfile.ZipFile(archive) as stream:
        for item in stream.infolist():
            path = pathlib.PurePosixPath(item.filename)
            if path.is_absolute() or ".." in path.parts or "\\" in item.filename:
                raise SystemExit(f"unsafe source package entry: {item.filename}")
        stream.extractall(target)


def run(repo: pathlib.Path, *argv: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(list(argv), cwd=repo, check=True, text=True)


def smoke(native: pathlib.Path, wasm: pathlib.Path, repo: pathlib.Path, release_version: str) -> None:
    expected = f"moonjust v{release_version} "
    version_result = subprocess.run([str(native), "--version"], text=True, capture_output=True, check=True)
    if not version_result.stdout.startswith(expected):
        raise SystemExit("cold source-package Native version differs")
    query = subprocess.run(
        [str(native), "--list", "--justfile", str(repo / "tests/fixtures/query/justfile")],
        text=True,
        capture_output=True,
        check=True,
    )
    if "Available recipes:" not in query.stdout:
        raise SystemExit("cold Native query corpus differs")
    execution = subprocess.run(
        [str(native), "--justfile", str(repo / "tests/fixtures/execution/line.justfile"), "build"],
        text=True,
        capture_output=True,
        check=True,
    )
    if execution.stdout != "hello world\nhidden\n" or execution.stderr != "echo hello world\nfalse\n":
        raise SystemExit("cold Native execution corpus differs")
    wasm_version = subprocess.run(
        ["moonrun", "--policy", str(repo / "policies/deny.toml"), str(wasm), "--", "--version"],
        text=True,
        capture_output=True,
        check=True,
    )
    if not wasm_version.stdout.startswith(expected):
        raise SystemExit("cold source-package wasm version differs")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=pathlib.Path, required=True)
    parser.add_argument("--repo", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    repo = args.repo.resolve()
    with tempfile.TemporaryDirectory(prefix="moonjust-source-rebuild-") as raw:
        work = pathlib.Path(raw)
        extract(args.archive.resolve(), work)
        release_version = version(work / "moon.mod")
        run(
            repo,
            sys.executable,
            str(repo / "tools/release/copy_resolved_dependencies.py"),
            "--manifest",
            str(work / "moon.mod"),
            "--source",
            str(repo / ".mooncakes"),
            "--target",
            str(work / ".mooncakes"),
        )
        environment = {"MOON_DEP_CACHE": "off", "MOON_BUILD_CACHE": "off"}
        subprocess.run(
            ["moon", "-C", str(work), "build", "--frozen", "--release", "--strip", "--target", "native", "cmd/just"],
            check=True,
            env={**os.environ, **environment},
        )
        subprocess.run(
            ["moon", "-C", str(work), "build", "--frozen", "--release", "--strip", "--target", "wasm", "cmd/just"],
            check=True,
            env={**os.environ, **environment},
        )
        native = work / "_build/native/release/build/cmd/just/just.exe"
        wasm = work / "_build/wasm/release/build/cmd/just/just.wasm"
        if not native.is_file() or not wasm.is_file():
            raise SystemExit("cold source-package artifact is missing")
        smoke(native, wasm, work, release_version)
    print("Release source package rebuilt from exact sources with caches disabled and corpus parity")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
