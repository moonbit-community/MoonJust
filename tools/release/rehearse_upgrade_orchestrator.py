#!/usr/bin/env python3
"""Build a previous source revision and rehearse candidate upgrade/rollback."""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def run(repo: Path, *argv: str, env: dict[str, str] | None = None, capture: bool = False) -> str:
    result = subprocess.run(list(argv), cwd=repo, check=True, text=True, capture_output=capture, env=env)
    return result.stdout if capture else ""


def target_platform() -> str:
    return {"Linux": "linux-x86_64", "Darwin": "macos-aarch64", "Windows": "windows-x86_64"}[platform.system()]


def extract_revision(repo: Path, revision: str, target: Path) -> None:
    archive = target.with_suffix(".zip")
    run(repo, "git", "archive", "--format=zip", "--output", str(archive), revision)
    target.mkdir(parents=True)
    with zipfile.ZipFile(archive) as stream:
        stream.extractall(target)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--previous-ref", default="fedf99f7a6a5f99e2b559b07931d009e162fbfce")
    parser.add_argument("--platform", default=None)
    args = parser.parse_args()
    repo = args.repo.resolve()
    target = args.platform or target_platform()
    extension = ".zip" if target.startswith("windows-") else ".tar.gz"
    environment = {**os.environ, "MOON_DEP_CACHE": "off", "MOON_BUILD_CACHE": "off"}
    with tempfile.TemporaryDirectory(prefix="moonjust-upgrade-orchestrator-") as raw:
        root = Path(raw)
        previous_source = root / "previous-source"
        extract_revision(repo, args.previous_ref, previous_source)
        run(
            repo,
            sys.executable,
            str(repo / "tools/release/copy_resolved_dependencies.py"),
            "--manifest",
            str(previous_source / "moon.mod"),
            "--source",
            str(repo / ".mooncakes"),
            "--target",
            str(previous_source / ".mooncakes"),
        )
        subprocess.run(
            ["moon", "-C", str(previous_source), "build", "--frozen", "--release", "--strip", "--target", "native", "cmd/just"],
            check=True,
            env=environment,
        )
        previous_binary = previous_source / "_build/native/release/build/cmd/just/just.exe"
        previous_stage = root / "previous-stage"
        previous_stage.mkdir()
        shutil.copy2(previous_binary, previous_stage / ("just.exe" if target.startswith("windows-") else "just"))
        previous_archive = repo / "_build/release-upgrade" / f"moonjust-0.7.0-alpha-{target}{extension}"
        previous_archive.parent.mkdir(parents=True, exist_ok=True)
        run(repo, sys.executable, str(repo / "tools/release/create_archive.py"), "--source", str(previous_stage), "--output", str(previous_archive))
        candidate_out = repo / "_build/release-upgrade/candidate"
        candidate = run(
            repo,
            sys.executable,
            "tools/release/build_artifacts.py",
            "--repo",
            str(repo),
            "--platform",
            target,
            "--out",
            str(candidate_out),
            capture=True,
            env={**environment, "MOONJUST_REQUIRE_CLEAN": "0"},
        ).strip().splitlines()[-1]
        run(
            repo,
            sys.executable,
            str(repo / "tools/release/rehearse_upgrade.py"),
            "--repo",
            str(repo),
            "--previous",
            str(previous_archive),
            "--candidate",
            candidate,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
