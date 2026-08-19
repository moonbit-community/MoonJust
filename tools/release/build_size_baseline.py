#!/usr/bin/env python3
"""Build a same-run merge-base artifact baseline for release size comparisons."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path


def run(command: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"command failed ({result.returncode}): {' '.join(command)}: {detail}")
    return (result.stdout + result.stderr).strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_artifact_size(repo: Path):
    path = repo / "tools/release/check_artifact_size.py"
    spec = importlib.util.spec_from_file_location("moonjust_artifact_size", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load artifact analyzer: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def extract_commit(repo: Path, commit: str, destination: Path) -> None:
    archive = subprocess.run(
        ["git", "-C", str(repo), "archive", commit],
        check=True,
        capture_output=True,
    ).stdout
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as source:
        source.extractall(destination)


def stage_archive(repo: Path, source: Path, native: Path, platform_name: str, output: Path) -> None:
    stage = output.parent / "stage"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    native_name = "just.exe" if platform_name.startswith("windows-") else "just"
    shutil.copy2(native, stage / native_name)
    os.chmod(stage / native_name, 0o755)
    for filename in ("LICENSE", "NOTICE", "README.mbt.md", "SECURITY.md", "CHANGELOG.md"):
        shutil.copy2(source / filename, stage / filename)
    run(
        [
            "python3",
            str(repo / "tools/release/create_archive.py"),
            "--source",
            str(stage),
            "--output",
            str(output),
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--base-ref", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = args.output.resolve()
    commit = run(["git", "-C", str(repo), "rev-parse", args.base_ref])
    with tempfile.TemporaryDirectory(prefix="moonjust-size-baseline-") as temporary:
        work = Path(temporary)
        extract_commit(repo, commit, work)
        environment = os.environ.copy()
        environment.update({"MOON_DEP_CACHE": "off", "MOON_BUILD_CACHE": "off"})
        environment.setdefault("SOURCE_DATE_EPOCH", "0")
        environment.setdefault("ZERO_AR_DATE", "1")
        # The merge-base may declare an older dependency revision than the
        # candidate checkout. Resolve it from the registry under this run's
        # latest MoonBit toolchain instead of silently comparing mixed trees.
        run(["moon", "-C", str(work), "update"], env=environment)
        run(["moon", "-C", str(work), "install"], env=environment)
        native_dir = work / "_build/native"
        wasm_dir = work / "_build/wasm"
        run(
            [
                "moon",
                "-C",
                str(work),
                "build",
                "--frozen",
                "--release",
                "--strip",
                "--target",
                "native",
                "--target-dir",
                str(native_dir),
                "cmd/just",
            ],
            env=environment,
        )
        run(
            [
                "moon",
                "-C",
                str(work),
                "build",
                "--frozen",
                "--release",
                "--strip",
                "--target",
                "wasm",
                "--target-dir",
                str(wasm_dir),
                "cmd/just",
            ],
            env=environment,
        )
        native = native_dir / "native/release/build/cmd/just/just.exe"
        wasm = wasm_dir / "wasm/release/build/cmd/just/just.wasm"
        if not native.is_file() or not wasm.is_file():
            raise RuntimeError("merge-base release artifacts are missing")
        archive_suffix = ".zip" if args.platform.startswith("windows-") else ".tar.gz"
        archive = work / f"moonjust-baseline{archive_suffix}"
        stage_archive(repo, work, native, args.platform, archive)
        analyzer = load_artifact_size(repo)
        record = {
            "schema_version": 1,
            "kind": "same-run-merge-base",
            "commit": commit,
            "platform": args.platform,
            "moon": run(["moon", "version", "--all"]),
            "native": analyzer.artifact_record(native, analyze=True),
            "wasm1": analyzer.artifact_record(wasm, analyze=True),
            "archive": analyzer.artifact_record(archive),
        }
        for name in ("native", "wasm1", "archive"):
            record[name]["path"] = f"merge-base/{name}"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"same-run merge-base size baseline: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, tarfile.TarError, json.JSONDecodeError) as error:
        raise SystemExit(f"size baseline error: {error}")
