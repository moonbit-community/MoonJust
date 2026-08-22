#!/usr/bin/env python3
"""Run each one-to-one MoonBit contract against pinned upstream provenance."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
import time
import uuid
from pathlib import Path


SCHEMA_VERSION = 2
UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"


def root() -> Path:
    return Path(__file__).resolve().parents[2]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest(value: object) -> str:
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


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
    parser.add_argument("--batch-output", type=Path)
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
    moonjust_commit = subprocess.run(
        ["git", "-C", str(root()), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    moonjust_tree = subprocess.run(
        ["git", "-C", str(root()), "rev-parse", "HEAD^{tree}"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    toolchain = subprocess.run(
        ["moon", "version", "--all"], cwd=root(), check=True, capture_output=True, text=True
    ).stdout.strip()

    batches: dict[tuple[str, str], list[dict[str, object]]] = {}
    for row in rows:
        verify_source(args.upstream_source, row)
        anchor = row["test_anchor"]
        assert isinstance(anchor, dict)
        for target in targets:
            target_name = "wasm1" if target == "wasm" else target
            if target_name not in row["targets"]:
                continue
            batches.setdefault((target, str(anchor["suite"])), []).append(row)

    results: list[dict[str, object]] = []
    batches_output: list[dict[str, object]] = []
    failed = False
    for (target, suite), batch_rows in sorted(batches.items()):
        target_name = "wasm1" if target == "wasm" else target
        command = [
            "moon",
            "test",
            "--frozen",
            "--target",
            target,
            suite,
            "--no-parallelize",
        ]
        started = time.monotonic_ns()
        started_at = time.time()
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
        batch_id = f"{target_name}:{suite}"
        detail = next(
            (
                line.strip()
                for text in (result.stderr, result.stdout)
                for line in text.splitlines()
                if line.strip()
            ),
            "no diagnostic output",
        )
        status = "PASS" if passed else "FAIL"
        print(
            f"{status} batch {batch_id} cases={len(batch_rows)} "
            f"exit={result.returncode}: {detail}",
            file=sys.stdout if passed else sys.stderr,
        )
        command_record = {
            "argv": command,
            "cwd": ".",
            "env_digest": digest({key: os.environ[key] for key in ("CI", "GITHUB_ACTIONS") if key in os.environ}),
        }
        batch_run_id = f"{moonjust_commit[:12]}-{uuid.uuid4().hex[:12]}"
        batches_output.append(
            {
                "schema_version": 2,
                "runner_version": "2.0",
                "run_id": batch_run_id,
                "stage": "compat",
                "mode": "contract",
                "commit_sha": moonjust_commit,
                "tree_sha": moonjust_tree,
                "baseline_sha": None,
                "host": {"system": platform.system(), "machine": platform.machine()},
                "profile": "debug",
                "toolchain": {"value": toolchain, "digest": digest(toolchain)},
                "dependencies": {"digest": digest({}), "manifests": []},
                "registry_refs": [],
                "artifact_hashes": {},
                "started_at": started_at,
                "batch_id": batch_id,
                "target": target_name,
                "suite": suite,
                "case_ids": [row["id"] for row in batch_rows],
                "case_count": len(batch_rows),
                "command": command_record,
                "started_at_ns": started,
                "duration_ms": elapsed_ms,
                "exit_code": result.returncode,
                "status": "passed" if passed else "failed",
                "classification": "correctness",
                "measurements": {
                    "case_ids": [row["id"] for row in batch_rows],
                    "stdout_sha256": hashlib.sha256(result.stdout.encode("utf-8")).hexdigest(),
                    "stderr_sha256": hashlib.sha256(result.stderr.encode("utf-8")).hexdigest(),
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                },
            }
        )
        stdout_digest = hashlib.sha256(result.stdout.encode("utf-8")).hexdigest()
        stderr_digest = hashlib.sha256(result.stderr.encode("utf-8")).hexdigest()
        for row in batch_rows:
            anchor = row["test_anchor"]
            assert isinstance(anchor, dict)
            record = {
                "schema_version": SCHEMA_VERSION,
                "runner_version": "2.0",
                "run_id": f"{moonjust_commit[:12]}-{uuid.uuid4().hex[:12]}",
                "stage": "compat",
                "mode": "contract",
                "commit_sha": moonjust_commit,
                "tree_sha": moonjust_tree,
                "baseline_sha": None,
                "host": {
                    "system": platform.system(),
                    "machine": platform.machine(),
                },
                "profile": "debug",
                "toolchain": {"value": toolchain, "digest": digest(toolchain)},
                "dependencies": {"digest": digest({}), "manifests": []},
                "registry_refs": [],
                "artifact_hashes": {},
                "started_at": started_at,
                "duration_ms": elapsed_ms,
                "exit_code": result.returncode,
                "case_id": row["id"],
                "upstream_name": row["upstream_name"],
                "upstream_commit": UPSTREAM_COMMIT,
                "upstream_source": row["upstream_source"],
                "target": target_name,
                "suite": anchor["suite"],
                "test_name": anchor["test_name"],
                "passed": passed,
                "status": "passed" if passed else "failed",
                "classification": "correctness",
                "batch_id": batch_id,
                "batch_case_count": len(batch_rows),
                "batch_elapsed_ms": elapsed_ms,
                "command": command_record,
                "batch_evidence": "batches.jsonl",
                "stdout_sha256": stdout_digest,
                "stderr_sha256": stderr_digest,
                "measurements": {
                    "case_id": row["id"],
                    "input_digest": digest({"upstream_name": row["upstream_name"], "anchor": anchor}),
                    "expected_result": {"passed": True, "target": target_name},
                    "batch_id": batch_id,
                },
            }
            results.append(record)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(json.dumps(row, sort_keys=True) + "\n" for row in results),
        encoding="utf-8",
    )
    batch_output = args.batch_output or args.output.with_name("batches.jsonl")
    batch_output.parent.mkdir(parents=True, exist_ok=True)
    batch_output.write_text(
        "".join(json.dumps(row, sort_keys=True) + "\n" for row in batches_output),
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
