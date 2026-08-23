#!/usr/bin/env python3
"""Compare migration-era and current performance evidence inventories."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path
from typing import Any


MODULE_PATH = Path(__file__).with_name("benchmark.py")
SPEC = importlib.util.spec_from_file_location("moonjust_benchmark", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _commands(value: dict[str, Any]) -> dict[tuple[str, str], tuple[str, ...]]:
    result: dict[tuple[str, str], tuple[str, ...]] = {}
    fixtures = value.get("fixtures", {})
    if not isinstance(fixtures, dict):
        return result
    for workload, entry in fixtures.items():
        if not isinstance(workload, str) or not isinstance(entry, dict):
            continue
        commands = entry.get("commands", {})
        if not isinstance(commands, dict):
            continue
        for kind, command in commands.items():
            if not isinstance(kind, str) or not isinstance(command, list):
                continue
            if not all(isinstance(part, str) for part in command):
                continue
            normalized = tuple(
                "<fixture>" if "/moonjust-benchmark-" in part else part
                for part in command
            )
            result[(workload, kind)] = normalized
    return result


def _classifications(value: dict[str, Any]) -> dict[str, tuple[str, ...]]:
    result: dict[str, tuple[str, ...]] = {}
    workloads = value.get("workloads", {})
    if not isinstance(workloads, dict):
        return result
    for workload, entries in workloads.items():
        if not isinstance(workload, str) or not isinstance(entries, dict):
            continue
        result[workload] = tuple(sorted(str(kind) for kind in entries))
    return result


def _invalid_samples(value: dict[str, Any]) -> list[str]:
    invalid: list[str] = []
    raw_samples = value.get("raw_samples", {})
    path = raw_samples.get("path") if isinstance(raw_samples, dict) else None
    if not isinstance(path, str) or not Path(path).is_file():
        return invalid
    for line_number, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            invalid.append(f"line {line_number}: invalid JSON")
            continue
        if not isinstance(row, dict) or row.get("exit_code") != 0:
            invalid.append(f"line {line_number}: non-zero exit code")
            continue
        phase = row.get("phase")
        field = "elapsed_ms" if phase in {"latency", "cold-warm"} else "peak_rss_kib"
        sample = row.get(field)
        if phase in {"latency", "cold-warm"} and (
            not isinstance(sample, (int, float))
            or not math.isfinite(float(sample))
            or float(sample) < 0
        ):
            invalid.append(f"line {line_number}: invalid latency sample")
        if phase == "cold-warm" and row.get("condition") not in {"cold", "warm"}:
            invalid.append(f"line {line_number}: invalid cold/warm condition")
        if phase == "cold-warm" and not isinstance(row.get("round"), int):
            invalid.append(f"line {line_number}: invalid cold/warm round")
        if phase not in {"latency", "memory", "cold-warm"}:
            invalid.append(f"line {line_number}: unknown phase")
    return invalid


def compare(legacy_path: Path, current_path: Path) -> dict[str, Any]:
    legacy = benchmark.read_evidence(legacy_path)
    current = benchmark.read_evidence(current_path)
    mismatches: list[str] = []
    legacy_commands = _commands(legacy)
    current_commands = _commands(current)
    if legacy_commands != current_commands:
        missing = sorted(set(legacy_commands) - set(current_commands))
        added = sorted(set(current_commands) - set(legacy_commands))
        mismatches.append(f"command inventory differs: missing={missing}, added={added}")
    if _classifications(legacy) != _classifications(current):
        mismatches.append("workload classification inventory differs")
    legacy_results = benchmark.evidence_result_set(legacy)
    current_results = benchmark.evidence_result_set(current)
    if legacy_results != current_results:
        mismatches.append("workload/target result inventory differs")
    invalid = _invalid_samples(legacy) + _invalid_samples(current)
    if invalid:
        mismatches.append(f"invalid samples: {len(invalid)}")
    return {
        "schema_version": 1,
        "status": "passed" if not mismatches else "failed",
        "legacy": {"path": str(legacy_path), "sha256": sha256(legacy_path)},
        "current": {"path": str(current_path), "sha256": sha256(current_path)},
        "inventories": {
            "legacy_commands": len(legacy_commands),
            "current_commands": len(current_commands),
            "legacy_results": len(legacy_results),
            "current_results": len(current_results),
        },
        "invalid_samples": invalid,
        "mismatches": mismatches,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--legacy", type=Path, required=True)
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = compare(args.legacy.resolve(), args.current.resolve())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if result["status"] != "passed":
        for mismatch in result["mismatches"]:
            print(f"performance shadow gate: {mismatch}", file=sys.stderr)
        return 1
    print(f"performance shadow gate passed: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
