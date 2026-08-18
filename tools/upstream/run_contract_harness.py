#!/usr/bin/env python3
"""Run each one-to-one MoonBit contract against pinned upstream provenance."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path


SCHEMA_VERSION = 1
UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"


def root() -> Path:
    return Path(__file__).resolve().parents[2]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def contracts(path: Path) -> list[dict[str, object]]:
    return [
        row
        for row in map(json.loads, path.read_text(encoding="utf-8").splitlines())
        if row.get("disposition") == "verified-contract"
    ]


def verify_source(upstream: Path, row: dict[str, object]) -> None:
    source = row.get("upstream_source")
    if not isinstance(source, dict):
        raise ValueError(f"{row['id']} has no upstream source provenance")
    path = upstream / str(source["path"])
    if not path.is_file():
        raise ValueError(f"{row['id']} upstream source is missing: {path}")
    actual = sha256(path)
    if actual != source["file_sha256"]:
        raise ValueError(
            f"{row['id']} upstream source digest {actual} differs from {source['file_sha256']}"
        )
    lines = path.read_text(encoding="utf-8").splitlines()
    line = int(source["line"])
    if line > len(lines) or not lines[line - 1].strip():
        raise ValueError(f"{row['id']} upstream source line is invalid: {path}:{line}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--map",
        type=Path,
        default=root() / "tests/upstream/just-1.57.0/test-map.jsonl",
    )
    parser.add_argument(
        "--upstream-source",
        type=Path,
        default=root() / "_build/upstream/just-1.57.0/source",
    )
    parser.add_argument("--case")
    parser.add_argument("--target", action="append", choices=("native", "wasm"))
    parser.add_argument(
        "--output",
        type=Path,
        default=root() / "_build/upstream-contracts/results.jsonl",
    )
    args = parser.parse_args()
    rows = contracts(args.map.resolve())
    if args.case is not None:
        rows = [row for row in rows if row["id"] == args.case]
        if len(rows) != 1:
            raise ValueError(f"contract case is not unique and verified: {args.case}")
    targets = args.target or ["native", "wasm"]
    commit = subprocess.run(
        ["git", "-C", str(args.upstream_source), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if commit != UPSTREAM_COMMIT:
        raise ValueError(f"upstream source is {commit}, expected {UPSTREAM_COMMIT}")

    results: list[dict[str, object]] = []
    failed = False
    for row in rows:
        verify_source(args.upstream_source, row)
        anchor = row["test_anchor"]
        assert isinstance(anchor, dict)
        for target in targets:
            target_name = "wasm1" if target == "wasm" else target
            if target_name not in row["targets"]:
                continue
            command = [
                "moon",
                "test",
                "--frozen",
                "--target",
                target,
                str(anchor["suite"]),
                "--filter",
                str(anchor["test_name"]),
                "--no-parallelize",
            ]
            started = time.monotonic_ns()
            result = subprocess.run(
                command,
                cwd=root(),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            elapsed_ms = (time.monotonic_ns() - started) / 1_000_000
            passed = result.returncode == 0
            failed = failed or not passed
            record = {
                "schema_version": SCHEMA_VERSION,
                "case_id": row["id"],
                "upstream_name": row["upstream_name"],
                "upstream_commit": UPSTREAM_COMMIT,
                "upstream_source": row["upstream_source"],
                "target": target_name,
                "suite": anchor["suite"],
                "test_name": anchor["test_name"],
                "passed": passed,
                "elapsed_ms": elapsed_ms,
                "command": command,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
            results.append(record)
            label = (
                f"{row['id']} {target_name} "
                f"{anchor['suite']}::{anchor['test_name']}"
            )
            if passed:
                print(f"PASS {label}")
            else:
                detail = next(
                    (
                        line.strip()
                        for text in (result.stderr, result.stdout)
                        for line in text.splitlines()
                        if line.strip()
                    ),
                    "no diagnostic output",
                )
                print(
                    f"FAIL {label} exit={result.returncode}: {detail}",
                    file=sys.stderr,
                )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(json.dumps(row, sort_keys=True) + "\n" for row in results),
        encoding="utf-8",
    )
    print(f"contract results written to {args.output}")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        print(f"contract harness error: {error}", file=sys.stderr)
        raise SystemExit(2)
