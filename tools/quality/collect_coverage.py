#!/usr/bin/env python3
"""Run one MoonBit coverage target and write isolated, traceable evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path


SCHEMA_VERSION = 1


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_record(path: Path, root: Path) -> dict[str, object]:
    return {
        "path": str(path.relative_to(root)),
        "bytes": path.stat().st_size,
        "sha256": sha256(path),
    }


def trace_files(repo: Path) -> list[Path]:
    build_root = repo / "_build"
    return sorted(
        path
        for path in build_root.glob("moonbit_coverage_*")
        if path.is_file()
    )


def source_files(repo: Path, target: str) -> list[Path]:
    root = repo / "_build" / target / "debug" / "test"
    return sorted(path for path in root.rglob("*.trace.source") if path.is_file())


def run(repo: Path, target: str, output: Path) -> None:
    subprocess.run(["moon", "coverage", "clean"], cwd=repo, check=True)
    started_ns = time.time_ns()
    subprocess.run(
        ["moon", "test", "--target", target, "--enable-coverage", "--no-parallelize"],
        cwd=repo,
        check=True,
    )

    sources = source_files(repo, target)
    traces = trace_files(repo)
    if not sources:
        raise RuntimeError(f"no {target} trace sources were generated")
    if not traces:
        raise RuntimeError(f"no {target} coverage traces were generated")
    stale = [path for path in traces if path.stat().st_mtime_ns < started_ns]
    if stale:
        raise RuntimeError(
            "stale coverage traces detected: "
            + ", ".join(str(path) for path in stale)
        )

    target_root = output / target
    trace_root = target_root / "traces"
    shutil.rmtree(target_root, ignore_errors=True)
    trace_root.mkdir(parents=True, exist_ok=True)
    copied_traces: list[Path] = []
    for trace in traces:
        destination = trace_root / trace.name
        shutil.copy2(trace, destination)
        copied_traces.append(destination)
        trace.unlink()

    report = output / f"{target}.raw.xml"
    command = [
        "moon_cove_report",
        *(str(path) for path in sources),
        *(item for trace in copied_traces for item in ("-t", str(trace))),
        "-f",
        "cobertura",
        "-o",
        str(report),
        "--source-paths",
        str(repo),
        "--ignore-missing-files",
    ]
    subprocess.run(command, cwd=repo, check=True)

    metadata = {
        "schema_version": SCHEMA_VERSION,
        "target": target,
        "commit": subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip(),
        "moon": subprocess.run(
            ["moon", "version", "--all"],
            cwd=repo,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip(),
        "sources": [file_record(path, repo) for path in sources],
        "traces": [file_record(path, output) for path in copied_traces],
        "report": file_record(report, output),
        "test_command": [
            "moon",
            "test",
            "--target",
            target,
            "--enable-coverage",
            "--no-parallelize",
        ],
    }
    (output / f"{target}.metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--target", choices=("native", "wasm"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    run(args.repo.resolve(), args.target, args.output.resolve())
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(f"coverage collection error: {error}")
