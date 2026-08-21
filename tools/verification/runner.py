#!/usr/bin/env python3
"""Layered verification runner with traceable one-build orchestration."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Iterable


Command = tuple[str, ...]


def command(*parts: str) -> Command:
    return tuple(parts)


VERIFY_PREFIX: tuple[Command, ...] = (
    command("moon", "fmt", "--check"),
    command("./tools/checks/architecture.sh"),
    command("./tools/upstream/verify_snapshot.sh"),
    command("./tools/differential/self_test.sh"),
    command("./tools/differential/real_smoke.sh"),
    command("python3", "./tools/upstream/evaluator_oracle.py", "--upstream", "./_build/upstream/just-1.57.0/target/release/just"),
    command("./tools/spikes/check_host_async.sh"),
    command("./tools/spikes/check_ecosystem.sh"),
    command("./tools/checks/inspect.sh"),
    command("./tools/checks/query.sh"),
    command("./tools/checks/hostfs.sh"),
    command("./tools/checks/dotenv.sh"),
    command("./tools/checks/invocation.sh"),
    command("./tools/checks/workdir.sh"),
    command("./tools/checks/environment.sh"),
    command("./tools/checks/executor.sh"),
    command("./tools/checks/runtime.sh"),
    command("./tools/checks/compatibility.sh"),
    command("./tools/checks/platform.sh"),
)

VERIFY_TAIL: tuple[Command, ...] = (
    command("moon", "check", "--target", "all", "--warn-list", "+73"),
    command("./_build/native/debug/build/cmd/just/just.exe", "--version"),
    command("moonrun", "--policy", "./policies/execute.toml", "./_build/wasm/debug/build/cmd/just/just.wasm", "--version"),
)

VERIFY_COMMANDS = VERIFY_PREFIX + VERIFY_TAIL

MODE_COMMANDS: dict[str, tuple[Command, ...]] = {
    "fast": (
        command("moon", "fmt", "--check"),
        command("moon", "check", "--target", "all", "--warn-list", "+73"),
        command("./tools/checks/test_target.sh", "native"),
    ),
    "verify": VERIFY_COMMANDS,
    "compat": (
        command("./tools/checks/compatibility.sh"),
        command("./tools/checks/platform.sh"),
    ),
    "release": VERIFY_PREFIX
    + (command("python3", "./tools/upstream/run_contract_harness.py"), command("./tools/checks/release.sh"))
    + VERIFY_TAIL,
}


def unique_commands(commands: Iterable[Command]) -> tuple[Command, ...]:
    seen: set[Command] = set()
    result: list[Command] = []
    for item in commands:
        if item not in seen:
            seen.add(item)
            result.append(item)
    return tuple(result)


def mode_commands(mode: str) -> tuple[Command, ...]:
    try:
        return unique_commands(MODE_COMMANDS[mode])
    except KeyError as error:
        raise ValueError(f"unknown verification mode: {mode}") from error


def build_key(source_sha: str, target: str, profile: str) -> str:
    payload = json.dumps(
        {"source_sha": source_sha, "target": target, "profile": profile},
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return hashlib.sha256(payload).hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class BuildRegistry:
    """Persistent registry whose entries are valid only with a matching artifact hash."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self._keys: set[str] = set()

    def claim(self, source_sha: str, target: str, profile: str) -> tuple[str, bool]:
        """Keep the old API for callers that only need deterministic key allocation."""
        key = build_key(source_sha, target, profile)
        marker = self.root / f"{key}.json"
        if key in self._keys or marker.is_file():
            self._keys.add(key)
            return key, False
        marker.write_text(
            json.dumps({"source_sha": source_sha, "target": target, "profile": profile, "key": key}, sort_keys=True)
            + "\n",
            encoding="utf-8",
        )
        self._keys.add(key)
        return key, True

    def ensure(
        self,
        source_sha: str,
        target: str,
        profile: str,
        command_line: Command,
        artifact: Path,
        cwd: Path,
        toolchain: str,
        execute: bool,
    ) -> dict[str, object]:
        key = build_key(source_sha, target, profile)
        marker = self.root / f"{key}.json"
        existing: dict[str, object] = {}
        if marker.is_file():
            try:
                value = json.loads(marker.read_text(encoding="utf-8"))
                if isinstance(value, dict):
                    existing = value
            except json.JSONDecodeError:
                existing = {}
        valid = (
            existing.get("key") == key
            and existing.get("artifact") == str(artifact)
            and existing.get("command") == list(command_line)
            and existing.get("toolchain") == toolchain
            and artifact.is_file()
            and existing.get("sha256") == sha256(artifact)
        )
        built = False
        if not valid:
            if execute:
                subprocess.run(command_line, cwd=cwd, check=True)
                if not artifact.is_file():
                    raise RuntimeError(f"build did not produce {artifact}")
            built = True
            if artifact.is_file():
                metadata = {
                    "key": key,
                    "source_sha": source_sha,
                    "target": target,
                    "profile": profile,
                    "command": list(command_line),
                    "artifact": str(artifact),
                    "bytes": artifact.stat().st_size,
                    "sha256": sha256(artifact),
                    "toolchain": toolchain,
                }
                temporary = marker.with_suffix(".tmp")
                temporary.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
                temporary.replace(marker)
        self._keys.add(key)
        return {
            "key": key,
            "target": target,
            "profile": profile,
            "artifact": str(artifact),
            "bytes": artifact.stat().st_size if artifact.is_file() else None,
            "sha256": sha256(artifact) if artifact.is_file() else None,
            "reused": not built,
        }


def tool_output(command_line: Command, cwd: Path) -> str:
    return subprocess.run(command_line, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def prepare_builds(repo: Path, execute: bool = True) -> tuple[dict[str, str], list[dict[str, object]]]:
    source_sha = tool_output(("git", "rev-parse", "HEAD"), repo)
    toolchain = tool_output(("moon", "version", "--all"), repo)
    registry = BuildRegistry(repo / "_build" / "verification" / "registry")
    oracle = repo / "_build/upstream/just-1.57.0/target/release/just"
    native = repo / "_build/native/debug/build/cmd/just/just.exe"
    wasm = repo / "_build/wasm/debug/build/cmd/just/just.wasm"
    builds: list[dict[str, object]] = []
    builds.append(registry.ensure(source_sha, "official", "just-1.57.0", ("./tools/upstream/build_oracle.sh",), oracle, repo, toolchain, execute))
    builds.append(registry.ensure(source_sha, "native", "debug", ("moon", "build", "--target", "native", "cmd/just"), native, repo, toolchain, execute))
    builds.append(registry.ensure(source_sha, "wasm", "debug", ("moon", "build", "--target", "wasm", "cmd/just"), wasm, repo, toolchain, execute))
    return {"MOONJUST_ORACLE_CANDIDATE": str(oracle), "MOONJUST_NATIVE_CANDIDATE": str(native), "MOONJUST_WASM_CANDIDATE": str(wasm)}, builds


def run(mode: str, repo: Path, dry_run: bool = False, evidence: Path | None = None) -> int:
    commands = mode_commands(mode)
    env = os.environ.copy()
    builds: list[dict[str, object]] = []
    if mode in {"verify", "compat", "release"}:
        prepared, builds = prepare_builds(repo, execute=not dry_run)
        env.update(prepared)
        env["MOONJUST_REUSE_BUILD"] = "1"
    records: list[dict[str, object]] = []
    failure: BaseException | None = None
    for item in commands:
        print("$ " + " ".join(item), flush=True)
        started = time.perf_counter()
        code = 0
        try:
            if not dry_run:
                subprocess.run(item, cwd=repo, env=env, check=True)
        except BaseException as error:
            code = error.returncode if isinstance(error, subprocess.CalledProcessError) else 1
            failure = error
        records.append({"command": list(item), "exit_code": code, "duration_seconds": time.perf_counter() - started})
        if failure is not None:
            break
    output = evidence or repo / "_build" / "verification" / f"{mode}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({"schema_version": 1, "mode": mode, "commit": tool_output(("git", "rev-parse", "HEAD"), repo), "toolchain": tool_output(("moon", "version", "--all"), repo), "builds": builds, "commands": records}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if failure is not None:
        raise failure
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=sorted(MODE_COMMANDS))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    return run(args.mode, args.repo.resolve(), args.dry_run, args.evidence.resolve() if args.evidence else None)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, RuntimeError, ValueError) as error:
        print(f"verification runner error: {error}", file=sys.stderr)
        raise SystemExit(1)
