#!/usr/bin/env python3
"""Build and stage one reproducible MoonJust release platform."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform as host_platform
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

import optimize_wasm


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(repo: Path, *argv: str, env: dict[str, str] | None = None) -> None:
    subprocess.run(list(argv), cwd=repo, check=True, env=env)


def version(repo: Path) -> str:
    match = re.search(r'^version\s*=\s*"([^"]+)"$', (repo / "moon.mod").read_text(encoding="utf-8"), re.MULTILINE)
    if match is None:
        raise RuntimeError("moon.mod has no version")
    return match.group(1)


def archive_source(source: Path, output: Path, repo: Path) -> None:
    run(repo, sys.executable, "tools/release/create_archive.py", "--source", str(source), "--output", str(output))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--platform", default=os.environ.get("MOONJUST_RELEASE_PLATFORM"))
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument("--wasm-asset", type=Path, default=None)
    args = parser.parse_args()
    repo = args.repo.resolve()
    current = {
        "Linux": "linux-x86_64",
        "Darwin": "macos-aarch64",
        "Windows": "windows-x86_64",
    }.get(host_platform.system())
    target = args.platform or current
    if target not in {"linux-x86_64", "macos-aarch64", "windows-x86_64"}:
        raise RuntimeError(f"invalid release platform: {target}")
    if target != current:
        raise RuntimeError(f"release platform {target} differs from builder {current}")
    release_version = version(repo)
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, check=True, capture_output=True, text=True).stdout.strip()
    if os.environ.get("MOONJUST_REQUIRE_CLEAN") == "1":
        dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=repo, check=True, capture_output=True, text=True).stdout.strip()
        if dirty:
            raise RuntimeError("release checkout is not clean")
    out = (args.out or Path(os.environ.get("MOONJUST_RELEASE_OUT", str(repo / "_build/release")))).resolve()
    build = out / "build"
    stage = out / "stage" / f"moonjust-{release_version}-{target}"
    if build.exists():
        shutil.rmtree(build)
    if stage.exists():
        shutil.rmtree(stage)
    env = os.environ.copy()
    env.update({"SOURCE_DATE_EPOCH": "0", "ZERO_AR_DATE": "1", "MOON_DEP_CACHE": "off", "MOON_BUILD_CACHE": "off"})
    run(repo, "moon", "build", "--frozen", "--release", "--strip", "--target", "native", "--target-dir", str(build), "cmd/just", env=env)
    native_source = build / "native" / "release" / "build" / "cmd/just" / "just.exe"
    if not native_source.is_file():
        raise RuntimeError(f"native release executable is missing: {native_source}")
    if target.startswith("windows"):
        run(repo, sys.executable, "tools/release/normalize_pe_timestamp.py", str(native_source))
    stage.mkdir(parents=True, exist_ok=True)
    native_name = "just.exe" if target.startswith("windows") else "just"
    shutil.copy2(native_source, stage / native_name)
    for filename in ("LICENSE", "NOTICE", "README.mbt.md", "SECURITY.md", "CHANGELOG.md"):
        shutil.copy2(repo / filename, stage / filename)
    run(repo, sys.executable, "tools/release/generate_supply_chain.py", "--repo", str(repo), "--artifact", str(stage / native_name), "--target", target, "--out", str(stage))
    run(repo, sys.executable, "tools/release/verify_supply_chain.py", "--repo", str(repo), "--artifact", str(stage / native_name), "--target", target, "--sbom", str(stage / "sbom.cdx.json"), "--provenance", str(stage / "provenance.intoto.json"))
    native_digest = sha256(stage / native_name)
    (stage / "SHA256SUMS").write_text(f"{native_digest}  {native_name}\n", encoding="utf-8")
    archive = out / f"moonjust-{release_version}-{target}{'.zip' if target.startswith('windows') else '.tar.gz'}"
    archive_source(stage, archive, repo)
    archive_digest = sha256(archive)
    (Path(str(archive) + ".sha256")).write_text(f"{archive_digest}  {archive.name}\n", encoding="utf-8")
    wasm_source = args.wasm_asset.resolve() if args.wasm_asset else None
    if wasm_source is None:
        wasm_build = out / "wasm-build"
        run(
            repo,
            sys.executable,
            "tools/release/build_wasm.py",
            "--repo",
            str(repo),
            "--target-dir",
            str(wasm_build),
            env=env,
        )
        wasm_source = wasm_build / "wasm" / "release" / "build" / "cmd/just" / "just.wasm"
    if not wasm_source.is_file():
        raise RuntimeError(f"wasm1 release executable is missing: {wasm_source}")
    optimize_wasm.read_optimizer_metadata(wasm_source)
    wasm_dir = out / "assets" / f"ZSeanYves/MoonJust@{release_version}" / "cmd/just"
    if wasm_dir.exists():
        shutil.rmtree(wasm_dir)
    wasm_dir.mkdir(parents=True, exist_ok=True)
    wasm = wasm_dir / "just.wasm"
    shutil.copy2(wasm_source, wasm)
    optimizer = optimize_wasm.optimizer_metadata_path(wasm)
    shutil.copy2(optimize_wasm.optimizer_metadata_path(wasm_source), optimizer)
    (wasm_dir / "just.wasm.sha256").write_text(f"{sha256(wasm)}  just.wasm\n", encoding="utf-8")
    run(repo, sys.executable, "tools/release/generate_supply_chain.py", "--repo", str(repo), "--artifact", str(wasm), "--target", "wasm1", "--out", str(wasm_dir))
    run(repo, sys.executable, "tools/release/verify_supply_chain.py", "--repo", str(repo), "--artifact", str(wasm), "--target", "wasm1", "--sbom", str(wasm_dir / "sbom.cdx.json"), "--provenance", str(wasm_dir / "provenance.intoto.json"))
    (out / f"build-{target}.json").write_text(json.dumps({
        "schema_version": 1, "version": release_version, "commit": commit, "platform": target,
        "native_sha256": native_digest, "archive": archive.name, "archive_sha256": archive_digest,
        "wasm_asset": f"assets/ZSeanYves/MoonJust@{release_version}/cmd/just/just.wasm", "wasm_sha256": sha256(wasm),
        "wasm_optimizer": f"assets/ZSeanYves/MoonJust@{release_version}/cmd/just/just.wasm.optimizer.json",
        "wasm_sbom": f"assets/ZSeanYves/MoonJust@{release_version}/cmd/just/sbom.cdx.json",
        "wasm_provenance": f"assets/ZSeanYves/MoonJust@{release_version}/cmd/just/provenance.intoto.json",
    }, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(archive)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, tomllib.TOMLDecodeError) as error:
        raise SystemExit(f"release artifact error: {error}")
