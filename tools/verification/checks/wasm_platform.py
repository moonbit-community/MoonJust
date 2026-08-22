#!/usr/bin/env python3
"""Run a small shared-wasm cross-host smoke gate."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path


EXPECTED_VERSION = "moonjust 0.7.0-alpha.1"


def fail(message: str) -> int:
    print(f"shared wasm gate failed: {message}", file=sys.stderr)
    return 1


def run(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(command, 124, "", "timed out after 30s\n")


def main() -> int:
    candidate = Path(os.environ.get("MOONJUST_WASM_CANDIDATE", ""))
    if not candidate.is_file():
        return fail(f"candidate is missing: {candidate}")
    policy = Path("policies/execute.toml").resolve()
    if not policy.is_file():
        return fail(f"execution policy is missing: {policy}")
    base = ["moonrun", "--policy", str(policy), str(candidate)]

    version = run([*base, "--", "--version"])
    if version.returncode != 0 or version.stdout.strip() != EXPECTED_VERSION:
        return fail(f"--version returned {version.returncode}: {version.stdout!r} {version.stderr!r}")

    with tempfile.TemporaryDirectory(prefix="moonjust-wasm-gate-") as directory:
        work = Path(directory)
        (work / "justfile").write_text(
            "hello:\n  echo shared-wasm-gate\n",
            encoding="utf-8",
        )
        listed = run([*base, "--", "--list", "--color", "never"], cwd=work)
        if listed.returncode != 0 or not any(line.strip() == "hello" for line in listed.stdout.splitlines()):
            return fail(f"--list returned {listed.returncode}: {listed.stdout!r} {listed.stderr!r}")
        executed = run([*base, "--", "hello"], cwd=work)
        if executed.returncode != 0 or executed.stdout.strip() != "shared-wasm-gate":
            return fail(f"recipe returned {executed.returncode}: {executed.stdout!r} {executed.stderr!r}")

    print("shared wasm cross-host gate passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
