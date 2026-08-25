#!/usr/bin/env python3
"""Generate a deterministic manual benchmark fixture and run MoonJust."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("workload", nargs="?", default="recipes-1000",
                        choices=("recipes-1000", "check", "format", "dag-1000"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    output = repo / "_build/performance" / f"profile-{args.workload}"
    output.mkdir(parents=True, exist_ok=True)
    fixture = output / "justfile"
    if args.workload == "dag-1000":
        text = "root: " + " ".join(f"node{index:04d}" for index in range(999)) + "\n"
        text += "".join(f"node{index:04d}:\n" for index in range(999))
        arguments = ["--dry-run", "root"]
    else:
        fixture.write_text("".join(f"r{index:04d}:\n" for index in range(1000)), encoding="utf-8")
        arguments = {"recipes-1000": ["--summary"], "check": ["--fmt", "--check"], "format": ["--fmt"]}[args.workload]
        text = fixture.read_text(encoding="utf-8")
    fixture.write_text(text, encoding="utf-8")
    command = [
        "moon", "-C", str(repo), "run", "--frozen", "--release", "--target", "native", "--profile", "cmd/just", "--",
        "--justfile", str(fixture), *arguments,
    ]
    result = subprocess.run(command, cwd=output, check=False)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
