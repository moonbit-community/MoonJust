#!/usr/bin/env python3
"""Aggregate hosted-platform performance evidence without timing gates."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


SCHEMA_VERSION = 4
REQUIRED_PLATFORMS = {"linux-x86_64", "macos-aarch64", "windows-x86_64"}
REQUIRED_WORKLOADS = {"project-modules", "project-parameters", "project-execution"}
REQUIRED_KINDS = ("official", "candidate-native", "candidate-wasm")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def nested_report(value: dict[str, object], path: Path) -> dict[str, object]:
    if value.get("schema_version") != 2:
        raise ValueError(f"runner evidence schema is not v2: {path}")
    measurements = value.get("measurements")
    if not isinstance(measurements, dict) or not isinstance(measurements.get("report"), dict):
        raise ValueError(f"runner evidence has no performance report: {path}")
    return measurements["report"]


def validate_cold_warm(report: dict[str, object], path: Path) -> None:
    if report.get("status") != "passed":
        raise ValueError(f"cloud benchmark did not pass execution checks: {path}")
    cold_warm = report.get("cold_warm")
    if not isinstance(cold_warm, dict):
        raise ValueError(f"cloud report has no cold/warm evidence: {path}")
    if cold_warm.get("enabled") is not True or cold_warm.get("rounds") != 3 or cold_warm.get("warmups_per_round") != 5:
        raise ValueError(f"cloud report cold/warm policy changed: {path}")
    workloads = cold_warm.get("workloads")
    if not isinstance(workloads, dict) or set(workloads) != REQUIRED_WORKLOADS:
        raise ValueError(f"cloud report workload inventory is incomplete: {path}")
    for workload in sorted(REQUIRED_WORKLOADS):
        entries = workloads[workload]
        if not isinstance(entries, dict):
            raise ValueError(f"cloud report workload is malformed: {path}:{workload}")
        for kind in REQUIRED_KINDS:
            conditions = entries.get(kind)
            if not isinstance(conditions, dict):
                raise ValueError(f"cloud report artifact is missing: {path}:{workload}/{kind}")
            for condition in ("cold", "warm"):
                summary = conditions.get(condition)
                if not isinstance(summary, dict) or summary.get("latency_samples") != 3:
                    raise ValueError(f"cloud report sample count is invalid: {path}:{workload}/{kind}/{condition}")


def aggregate(reports: dict[str, Path], expected_sha: str, output: Path) -> None:
    if set(reports) != REQUIRED_PLATFORMS:
        raise ValueError("cloud performance must cover exactly " + ", ".join(sorted(REQUIRED_PLATFORMS)))
    platforms: dict[str, object] = {}
    statuses: dict[str, str] = {}
    moon_values: set[str] = set()
    for platform_name, path in sorted(reports.items()):
        value = load(path)
        if value.get("commit_sha") != expected_sha:
            raise ValueError(f"cloud evidence commit differs from exact head: {path}")
        report = nested_report(value, path)
        validate_cold_warm(report, path)
        if isinstance(report.get("moon"), str):
            moon_values.add(str(report["moon"]))
        platforms[platform_name] = {
            "path": str(path),
            "sha256": sha256(path),
            "commit_sha": value["commit_sha"],
            "tree_sha": value.get("tree_sha"),
            "host": value.get("host"),
            "status": report.get("status"),
            "report": report,
        }
        statuses[platform_name] = str(report.get("status"))
    result = {
        "schema_version": SCHEMA_VERSION,
        "status": "passed",
        "commit": expected_sha,
        "provenance": {
            "source_statuses": statuses,
        },
        "moon": next(iter(moon_values)) if len(moon_values) == 1 else None,
        "machine": {"platforms": sorted(REQUIRED_PLATFORMS)},
        "configuration": {
            "mode": "report-only",
            "platforms": sorted(REQUIRED_PLATFORMS),
        },
        "platform_reports": platforms,
        "cold_warm": {
            "enabled": True,
            "rounds": 3,
            "warmups_per_round": 5,
            "workloads": sorted(REQUIRED_WORKLOADS),
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-sha", required=True)
    parser.add_argument("--report", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    reports: dict[str, Path] = {}
    for assignment in args.report:
        name, separator, raw_path = assignment.partition("=")
        if not separator or not name or not raw_path or name in reports:
            raise ValueError(f"expected unique PLATFORM=PATH, observed {assignment!r}")
        path = Path(raw_path).resolve()
        if not path.is_file():
            raise ValueError(f"cloud performance report is missing: {path}")
        reports[name] = path
    aggregate(reports, args.expected_sha, args.output.resolve())
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"cloud performance aggregation error: {error}")
