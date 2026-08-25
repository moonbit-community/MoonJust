#!/usr/bin/env python3
"""Run a small shared-wasm cross-host smoke gate."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path = [entry for entry in sys.path if Path(entry or ".").resolve() != Path(__file__).parent.resolve()]
import platform


EXPECTED_VERSION = "moonjust v0.1.1"


def fail(message: str) -> int:
    print(f"shared wasm gate failed: {message}", file=sys.stderr)
    return 1


def host_runtime_env() -> dict[str, str]:
    """Tell portable MoonJust which host owns the shared Wasm process."""
    system = platform.system().lower()
    operating_system = {
        "darwin": "macos",
        "windows": "windows",
        "linux": "linux",
    }.get(system, system)
    machine = platform.machine().lower()
    architecture = {
        "amd64": "amd64",
        "x86_64": "amd64",
        "arm64": "arm64",
        "aarch64": "arm64",
    }.get(machine, machine)
    environment = os.environ.copy()
    environment["MOONJUST_OS"] = operating_system
    environment["MOONJUST_ARCH"] = architecture
    return environment


def run(
    command: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            cwd=cwd,
            env=env,
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
    environment = host_runtime_env()

    version = run([*base, "--", "--version"], env=environment)
    if version.returncode != 0 or version.stdout.strip() != EXPECTED_VERSION:
        return fail(f"--version returned {version.returncode}: {version.stdout!r} {version.stderr!r}")

    with tempfile.TemporaryDirectory(prefix="moonjust-wasm-gate-") as directory:
        work = Path(directory)
        windows_shell = "set windows-shell := ['cmd.exe', '/D', '/C']\n\n" if os.name == "nt" else ""
        (work / "justfile").write_text(
            windows_shell + "hello:\n  echo shared-wasm-gate\n",
            encoding="utf-8",
        )
        listed = run(
            [*base, "--", "--list", "--color", "never"],
            cwd=work,
            env=environment,
        )
        if listed.returncode != 0 or not any(line.strip() == "hello" for line in listed.stdout.splitlines()):
            return fail(f"--list returned {listed.returncode}: {listed.stdout!r} {listed.stderr!r}")
        executed = run([*base, "--", "hello"], cwd=work, env=environment)
        if executed.returncode != 0 or executed.stdout.strip() != "shared-wasm-gate":
            return fail(f"recipe returned {executed.returncode}: {executed.stdout!r} {executed.stderr!r}")

    print("shared wasm cross-host gate passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
