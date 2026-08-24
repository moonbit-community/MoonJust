#!/usr/bin/env python3
"""Build the pinned upstream just oracle using native subprocess calls."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
from pathlib import Path


TAG = "1.57.0"
COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
LOCK_SHA256 = "907adacb2b2a3db5ed6be6f130e18aec6f869bdc8b5dc64a9ecb98484fbfb550"


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def git(repo: Path, *args: str) -> str:
    environment = os.environ.copy()
    for name in (
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX",
        "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_COMMON_DIR", "GIT_NAMESPACE",
    ):
        environment.pop(name, None)
    return subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True,
        text=True, env=environment,
    ).stdout.strip()


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    cache = Path(os.environ.get("MOONJUST_ORACLE_CACHE", str(repo / "_build/upstream/just-1.57.0"))).resolve()
    checkout = cache / "source"
    binary = cache / "target" / "release" / ("just.exe" if os.name == "nt" else "just")
    cache.mkdir(parents=True, exist_ok=True)
    if not (checkout / ".git").is_dir():
        temporary = cache / "source.clone"
        if temporary.exists():
            shutil.rmtree(temporary)
        subprocess.run(
            ["git", "clone", "--quiet", "--branch", TAG, "--depth", "1",
             "https://github.com/casey/just.git", str(temporary)],
            check=True,
        )
        if checkout.exists():
            shutil.rmtree(checkout)
        temporary.replace(checkout)
    if git(checkout, "rev-parse", "--is-inside-work-tree") != "true":
        raise RuntimeError("oracle checkout is not a git worktree")
    if git(checkout, "rev-parse", f"refs/tags/{TAG}^{{commit}}") != COMMIT:
        raise RuntimeError("pinned oracle tag commit changed")
    lock = checkout / "Cargo.lock"
    if not lock.is_file() or digest(lock) != LOCK_SHA256:
        raise RuntimeError("pinned oracle Cargo.lock hash changed")
    environment = os.environ.copy()
    environment["CARGO_TARGET_DIR"] = str(cache / "target")
    subprocess.run(
        ["cargo", "build", "--quiet", "--release", "--manifest-path", str(checkout / "Cargo.toml"), "--locked"],
        check=True,
        env=environment,
    )
    if not binary.is_file():
        raise RuntimeError(f"cargo did not produce {binary}")
    version = subprocess.run([str(binary), "--version"], check=True, capture_output=True, text=True).stdout.strip()
    if f"just {TAG}" not in version:
        raise RuntimeError(f"oracle version output changed: {version}")
    print(f"source={checkout}")
    print(f"tag={TAG}")
    print(f"commit={COMMIT}")
    print(f"cargo_lock_sha256={digest(lock)}")
    print(f"binary={binary}")
    print(f"binary_sha256={digest(binary)}")
    print(f"version={version}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(f"upstream oracle error: {error}")
