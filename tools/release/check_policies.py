#!/usr/bin/env python3
"""Exercise the release MoonRun policies through the native Python runner."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import tempfile


def run(repo: pathlib.Path, *argv: str, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(list(argv), cwd=repo, check=not capture, text=True, capture_output=capture)


def expect_denied(command: list[str], pattern: str) -> None:
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode == 0 or re.search(pattern, result.stderr) is None:
        raise SystemExit(f"policy did not deny as expected: {' '.join(command)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    repo = args.repo.resolve()
    run(repo, "moon", "build", "--release", "--strip", "--target", "wasm", "cmd/just")
    wasm = repo / "_build/wasm/release/build/cmd/just/just.wasm"
    if not wasm.is_file():
        raise SystemExit("wasm policy artifact is missing")
    with tempfile.TemporaryDirectory(prefix="moonjust-policy-") as raw:
        work = pathlib.Path(raw)
        denied = ["CapabilityUnavailable(Environment)", "Sandbox policy blocked file read"]
        expect_denied(
            ["moonrun", "--policy", str(repo / "policies/deny.toml"), str(wasm), "--list", "--justfile", str(repo / "tests/fixtures/query/justfile")],
            "|".join(re.escape(value) for value in denied),
        )
        default_policy = work / "default.toml"
        default_policy.write_text("[net]\ndns = []\nconnect = []\nbind = []\n", encoding="utf-8")
        expect_denied(
            ["moonrun", "--policy", str(default_policy), str(wasm), "--list", "--justfile", str(repo / "tests/fixtures/query/justfile")],
            "|".join(re.escape(value) for value in denied),
        )
        inspect = run(
            repo,
            "moonrun",
            "--policy",
            str(repo / "policies/inspect.toml"),
            str(wasm),
            "--list",
            "--justfile",
            str(repo / "tests/fixtures/query/justfile"),
            capture=True,
        )
        if "Available recipes:" not in inspect.stdout:
            raise SystemExit("inspect policy did not allow read-only query")
        execution = run(
            repo,
            "moonrun",
            "--policy",
            str(repo / "policies/ci.toml"),
            str(wasm),
            "--justfile",
            str(repo / "tests/fixtures/execution/line.justfile"),
            "build",
            capture=True,
        )
        if "hello world" not in execution.stdout:
            raise SystemExit("CI policy did not allow the execution corpus")
        explicit = run(
            repo,
            "moonrun",
            "--policy",
            str(repo / "policies/execute.toml"),
            str(wasm),
            "--justfile",
            str(repo / "tests/fixtures/execution/line.justfile"),
            "build",
            capture=True,
        )
        if explicit.stdout != execution.stdout:
            raise SystemExit("CI and explicit allow execution output differs")
    print("Release policies verified: explicit deny, default deny, inspect and controlled/full allow")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
