#!/usr/bin/env python3
"""Run the complete local release engineering gate."""

from __future__ import annotations

import argparse
import os
import platform
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def run(repo: Path, *argv: str, env: dict[str, str] | None = None) -> None:
    subprocess.run(list(argv), cwd=repo, check=True, env=env)


def version(repo: Path) -> str:
    match = re.search(
        r'^version\s*=\s*"([^"]+)"$',
        (repo / "moon.mod").read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if match is None:
        raise RuntimeError("moon.mod has no version")
    return match.group(1)


def target_platform() -> str:
    return {
        "Linux": "linux-x86_64",
        "Darwin": "macos-aarch64",
        "Windows": "windows-x86_64",
    }[platform.system()]


def require_publication_files(repo: Path, release_version: str) -> None:
    if release_version != "0.1.0":
        raise RuntimeError("module version differs from release identity")
    manifest = repo / "compat/release-readiness.toml"
    coordinate = f'coordinate = "ZSeanYves/MoonJust/cmd/just@{release_version}"'
    if coordinate not in manifest.read_text(encoding="utf-8").splitlines():
        raise RuntimeError("MoonX coordinate differs")
    required = (
        "api/API.mbt.md",
        "docs/API.md",
        "docs/RELEASE_POLICY.md",
        "LICENSE",
        "NOTICE",
        "README.mbt.md",
        "SECURITY.md",
        "CHANGELOG.md",
    )
    for relative in required:
        path = repo / relative
        if not path.is_file() or not path.stat().st_size:
            raise RuntimeError(f"required publication file is missing: {relative}")


def package_source(repo: Path, release_version: str) -> Path:
    run(repo, "moon", "package")
    candidates = (
        repo / f"_build/package/moonbit-community-MoonJust-{release_version}.zip",
        repo / f"_build/publish/moonbit-community-MoonJust-{release_version}.zip",
        repo / f"_build/publish/ZSeanYves-MoonJust-{release_version}.zip",
    )
    for archive in candidates:
        if archive.is_file():
            return archive
    raise RuntimeError("moon package archive is missing")


def build_profiles(repo: Path) -> None:
    run(repo, sys.executable, "tools/runner.py", "build", "--target", "native", "--profile", "release")
    run(repo, sys.executable, "tools/runner.py", "build", "--target", "wasm1", "--profile", "release")
    environment = os.environ.copy()
    environment.update(
        {
            "MOONJUST_NATIVE_CANDIDATE": str(repo / "_build/native/release/build/cmd/just/just.exe"),
            "MOONJUST_WASM_CANDIDATE": str(repo / "_build/wasm/release/build/cmd/just/just.wasm"),
        }
    )
    run(repo, sys.executable, "tools/verification/checks/compatibility.py", env=environment)
    run(repo, sys.executable, "tools/runner.py", "coverage", "--target", "native")
    run(repo, sys.executable, "tools/runner.py", "coverage", "--target", "wasm")
    run(repo, sys.executable, "tools/runner.py", "coverage", "--target", "merge")


def build_release_artifact(repo: Path, target: str) -> Path:
    environment = os.environ.copy()
    environment.update(
        {
            "MOONJUST_RELEASE_PLATFORM": target,
            "MOONJUST_REQUIRE_CLEAN": "1",
            "SOURCE_DATE_EPOCH": "0",
            "ZERO_AR_DATE": "1",
        }
    )
    result = subprocess.run(
        [
            sys.executable,
            "tools/release/build_artifacts.py",
            "--repo",
            str(repo),
            "--platform",
            target,
        ],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    return Path(result.stdout.strip().splitlines()[-1])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=ROOT)
    args = parser.parse_args()
    repo = args.repo.resolve()
    release_version = version(repo)
    require_publication_files(repo, release_version)

    run(repo, "moon", "check", "--target", "all", "--warn-list", "+73")
    run(repo, sys.executable, "tools/upstream/verify_manifest.py", "--release")
    run(repo, sys.executable, "tools/release/check_dependencies.py")
    archive = package_source(repo, release_version)
    run(repo, sys.executable, "tools/release/verify_source_package.py", "--archive", str(archive))
    build_profiles(repo)

    target = target_platform()
    run(
        repo,
        sys.executable,
        "tools/release/build_size_baseline.py",
        "--repo",
        str(repo),
        "--base-ref",
        "origin/main",
        "--platform",
        target,
        "--output",
        str(repo / "_build/size-baseline.json"),
    )
    run(
        repo,
        sys.executable,
        "tools/release/check_artifact_size.py",
        "--baseline-report",
        str(repo / "_build/size-baseline.json"),
        "--repo",
        str(repo),
        "--native",
        str(repo / "_build/native/release/build/cmd/just/just.exe"),
        "--wasm",
        str(repo / "_build/wasm/release/build/cmd/just/just.wasm"),
        "--output",
        str(repo / "_build/release/artifact-size.json"),
    )
    run(repo, sys.executable, "tools/release/rebuild_source_package.py", "--archive", str(archive))
    run(repo, sys.executable, "tools/release/check_repeatable_build.py")
    run(repo, sys.executable, "tools/release/check_policies.py")

    artifact = build_release_artifact(repo, target)
    run(
        repo,
        sys.executable,
        "tools/release/verify_bundle.py",
        "--repo",
        str(repo),
        "--archive",
        str(artifact),
        "--platform",
        target,
    )
    run(
        repo,
        sys.executable,
        "tools/release/check_tamper_resistance.py",
        "--repo",
        str(repo),
        "--archive",
        str(artifact),
        "--platform",
        target,
    )
    run(
        repo,
        sys.executable,
        "tools/verification/ci.py",
        "verify-moonx",
        "--repo",
        str(repo),
        "--registry",
        str(repo / "_build/release"),
    )
    run(repo, sys.executable, "tools/release/rehearse_upgrade_orchestrator.py", "--repo", str(repo))
    run(repo, sys.executable, "tools/runner.py", "test-tools")
    print("Release engineering gate passed: metadata, policies, package, artifacts, MoonX and supply chain")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(f"release gate error: {error}")
