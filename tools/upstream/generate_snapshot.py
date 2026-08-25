#!/usr/bin/env python3
"""Generate the pinned upstream test registration snapshot."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import tempfile
from pathlib import Path


TAG = "1.57.0"
COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
EXPECTED_COUNT = 2417


def clean_git_environment() -> dict[str, str]:
    environment = os.environ.copy()
    for name in (
        "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX",
        "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_COMMON_DIR", "GIT_NAMESPACE",
    ):
        environment.pop(name, None)
    return environment


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("checkout", nargs="?", type=Path)
    args = parser.parse_args()
    temporary: tempfile.TemporaryDirectory[str] | None = None
    try:
        if args.checkout is not None:
            checkout = args.checkout.resolve()
        else:
            temporary = tempfile.TemporaryDirectory(prefix="moonjust-upstream-")
            checkout = Path(temporary.name) / "just"
            subprocess.run(
                ["git", "clone", "--quiet", "--depth", "1", "--branch", TAG,
                 "https://github.com/casey/just.git", str(checkout)],
                check=True,
                env=clean_git_environment(),
            )
        actual = subprocess.run(
            ["git", "-C", str(checkout), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
            env=clean_git_environment(),
        ).stdout.strip()
        if actual != COMMIT:
            raise RuntimeError(f"expected just commit {COMMIT}, found {actual}")
        listed = subprocess.run(
            ["cargo", "test", "--", "--list"],
            cwd=checkout,
            check=True,
            capture_output=True,
            text=True,
            env=os.environ.copy(),
        ).stdout
        names = sorted(
            match.group(1)
            for line in listed.splitlines()
            if (match := re.fullmatch(r"(.*): test", line)) is not None
        )
        if len(names) != EXPECTED_COUNT:
            raise RuntimeError(f"expected {EXPECTED_COUNT} test registrations, found {len(names)}")
        output = repo / "tests/upstream/just-1.57.0/test-list.txt"
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary_output = output.with_name(f".{output.name}.tmp")
        temporary_output.write_text("\n".join(names) + "\n", encoding="utf-8")
        temporary_output.replace(output)
        print(f"{output}: {len(names)} registrations")
        return 0
    finally:
        if temporary is not None:
            temporary.cleanup()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(f"upstream snapshot error: {error}")
