#!/usr/bin/env python3
"""Run the portable Native platform smoke without a shell wrapper."""

from __future__ import annotations

import os
import subprocess
import tempfile
import sys
from pathlib import Path

sys.path = [entry for entry in sys.path if Path(entry or ".").resolve() != Path(__file__).parent.resolve()]
import platform as host_platform


def run(cli: Path, cwd: Path, *args: str, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(cli), *args], cwd=cwd, input=input_text, capture_output=True, text=True,
        encoding="utf-8", errors="replace", check=False,
    )


def main() -> int:
    repo = Path(__file__).resolve().parents[3]
    if os.environ.get("MOONJUST_PLATFORM_SKIP_TESTS") != "1":
        for package in ("src/host", "src/host_native", "src/host_process", "src/environment", "src/executor", "src/application"):
            subprocess.run(["moon", "test", "--target", "native", package], cwd=repo, check=True)
    cli = Path(os.environ.get("MOONJUST_NATIVE_CANDIDATE", str(repo / "_build/native/debug/build/cmd/just/just.exe")))
    if not cli.is_file():
        raise SystemExit(f"Platform gate failed: Native CLI artifact is missing: {cli}")
    system = host_platform.system()
    expected = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(system)
    if expected is None:
        raise SystemExit(f"Platform gate failed: unsupported runner operating system: {system}")
    with tempfile.TemporaryDirectory(prefix="moonjust-platform-") as raw:
        work = Path(raw)
        if system == "Windows":
            justfile = "set windows-shell := ['cmd.exe', '/D', '/C']\n\nplatform:\n  echo {{os()}}\n  echo {{arch()}}\n\nalpha:\n  echo platform-choice\n"
        else:
            justfile = "platform:\n  echo {{os()}}\n  echo {{arch()}}\n\nalpha:\n  echo platform-choice\n"
        (work / "justfile").write_text(justfile, encoding="utf-8")
        result = run(cli, work, "--justfile", str(work / "justfile"), "platform")
        if result.returncode != 0:
            raise SystemExit(f"Platform recipe failed:\n{result.stdout}{result.stderr}")
        lines = [line.strip().rstrip("\r") for line in result.stdout.splitlines() if line.strip()]
        if len(lines) < 2 or lines[0] != expected or lines[1] in {"", "unknown"}:
            raise SystemExit(f"Platform probe mismatch: {lines!r}")
        result = run(cli, work, "--justfile", str(work / "justfile"), "alpha")
        if result.returncode != 0 or "platform-choice" not in result.stdout:
            raise SystemExit("platform recipe dispatch failed")
    print(f"Platform gate passed ({expected}/{host_platform.machine().lower()}, Native CLI)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
