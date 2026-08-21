#!/usr/bin/env python3
"""Layered verification runner with deterministic command planning.

The shell entry points remain the compatibility surface. This module owns the
mode inventory so CI and local callers can select a narrow gate without
reimplementing build/test ordering.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
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
    command("./tools/checks/test_target.sh", "native"),
    command("./tools/checks/test_target.sh", "wasm"),
    command("moon", "run", "--target", "native", "cmd/just", "--", "--version"),
    command("moon", "run", "--target", "wasm", "cmd/just", "--", "--version"),
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
    "release": VERIFY_PREFIX + (command("./tools/checks/release.sh"),) + VERIFY_TAIL,
}


def unique_commands(commands: Iterable[Command]) -> tuple[Command, ...]:
    """Remove duplicate commands while preserving the first execution order."""
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


class BuildRegistry:
    """Small persistent registry for one-build-per-key orchestration."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self._keys: set[str] = set()

    def claim(self, source_sha: str, target: str, profile: str) -> tuple[str, bool]:
        key = build_key(source_sha, target, profile)
        marker = self.root / f"{key}.json"
        if key in self._keys or marker.is_file():
            self._keys.add(key)
            return key, False
        marker.write_text(
            json.dumps(
                {"source_sha": source_sha, "target": target, "profile": profile, "key": key},
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        self._keys.add(key)
        return key, True


def run(mode: str, repo: Path, dry_run: bool = False) -> int:
    commands = mode_commands(mode)
    for item in commands:
        print("$ " + " ".join(item), flush=True)
        if not dry_run:
            subprocess.run(item, cwd=repo, check=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=sorted(MODE_COMMANDS))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    return run(args.mode, args.repo.resolve(), args.dry_run)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"verification runner error: {error}", file=sys.stderr)
        raise SystemExit(1)
