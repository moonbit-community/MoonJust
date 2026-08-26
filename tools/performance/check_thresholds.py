#!/usr/bin/env python3
"""Enforce paired official/candidate performance thresholds.

The benchmark runner deliberately records observations only.  This module is
the policy boundary: it consumes one or more independent platform batches,
computes candidate/official ratios, and writes a machine-readable gate record.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
PLATFORMS = ("linux-x86_64", "macos-aarch64", "windows-x86_64")
WORKLOADS = (
    "startup",
    "recipes-10",
    "recipes-100",
    "recipes-1000",
    "recipes-5000",
    "check",
    "format",
    "dag-1000",
    "noops-100",
    "project-modules",
    "project-parameters",
    "project-execution",
)
REQUIRED_KINDS = ("official", "candidate-native", "candidate-wasm")
OFFICIAL_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def toolchain_signature(value: Any) -> tuple[str, str, str] | None:
    text = value.get("value", "") if isinstance(value, dict) else value
    if not isinstance(text, str):
        return None
    versions = []
    for name in ("moon", "moonc", "moonrun"):
        match = re.search(rf"\b{name} v?([0-9]+\.[0-9]+\.[0-9]+)", text)
        if match is None:
            return None
        versions.append(match.group(1))
    return tuple(versions)  # type: ignore[return-value]


def report_payload(value: dict[str, Any], path: Path) -> dict[str, Any]:
    measurements = value.get("measurements")
    payload = measurements.get("report") if isinstance(measurements, dict) else None
    if isinstance(payload, dict):
        return payload
    if isinstance(value.get("workloads"), dict):
        return value
    raise ValueError(f"performance report has no workloads: {path}")


def extract_batch(value: dict[str, Any], path: Path) -> dict[str, Any]:
    report = report_payload(value, path)
    if report.get("status") != "passed":
        raise ValueError(f"performance report is not passed: {path}")
    workloads = report.get("workloads")
    if not isinstance(workloads, dict) or set(workloads) != set(WORKLOADS):
        raise ValueError(f"performance report workload inventory is incomplete: {path}")
    result: dict[str, Any] = {}
    for workload in WORKLOADS:
        entries = workloads[workload]
        if not isinstance(entries, dict) or set(entries) != set(REQUIRED_KINDS):
            raise ValueError(f"performance report artifacts are incomplete: {path}:{workload}")
        official = entries["official"]
        if not isinstance(official, dict):
            raise ValueError(f"official observation is malformed: {path}:{workload}")
        official_median = float(official["median_ms"])
        official_p95 = float(official["p95_ms"])
        if official_median <= 0 or official_p95 <= 0:
            raise ValueError(f"official observation is non-positive: {path}:{workload}")
        result[workload] = {}
        for kind in ("candidate-native", "candidate-wasm"):
            sample = entries[kind]
            if not isinstance(sample, dict):
                raise ValueError(f"candidate observation is malformed: {path}:{workload}/{kind}")
            count = int(sample.get("latency_samples", 0))
            if count < 15:
                raise ValueError(f"incomplete latency samples: {path}:{workload}/{kind}")
            result[workload][kind.removeprefix("candidate-")] = {
                "median_ratio": float(sample["median_ms"]) / official_median,
                "p95_ratio": float(sample["p95_ms"]) / official_p95,
                "latency_samples": count,
                "official_median_ms": official_median,
                "official_p95_ms": official_p95,
                "candidate_median_ms": float(sample["median_ms"]),
                "candidate_p95_ms": float(sample["p95_ms"]),
            }
    return {
        "commit_sha": value.get("commit_sha", report.get("commit")),
        "tree_sha": value.get("tree_sha"),
        "toolchain": value.get("toolchain", report.get("moon")),
        "official_commit": report.get("provenance", {}).get("official_commit")
        if isinstance(report.get("provenance"), dict)
        else None,
        "workloads": result,
    }


def parse_assignments(assignments: list[str]) -> dict[str, list[Path]]:
    result: dict[str, list[Path]] = {platform: [] for platform in PLATFORMS}
    for assignment in assignments:
        platform, separator, raw_path = assignment.partition("=")
        if not separator or platform not in PLATFORMS or not raw_path:
            raise ValueError(f"expected PLATFORM=PATH, observed {assignment!r}")
        path = Path(raw_path).resolve()
        if path.is_file():
            result[platform].append(path)
    return result


def baseline_ratios(path: Path) -> dict[str, dict[str, dict[str, float]]]:
    value = load_json(path)
    if value.get("schema_version") != 1:
        raise ValueError(f"unsupported performance baseline schema: {path}")
    source = value.get("source")
    if not isinstance(source, dict) or not source.get("commit_sha"):
        raise ValueError(f"baseline has no source commit: {path}")
    if source.get("official_commit") != OFFICIAL_COMMIT:
        raise ValueError(f"baseline uses an unexpected official commit: {path}")
    if baseline_toolchain(path) is None:
        raise ValueError(f"baseline has no parseable MoonBit toolchain: {path}")
    platforms = value.get("platforms")
    if not isinstance(platforms, dict):
        raise ValueError(f"baseline has no platforms: {path}")
    result: dict[str, dict[str, dict[str, float]]] = {}
    for platform in PLATFORMS:
        entries = platforms.get(platform)
        if not isinstance(entries, dict):
            raise ValueError(f"baseline is missing platform: {platform}")
        result[platform] = {}
        for workload in WORKLOADS:
            item = entries.get(workload)
            if not isinstance(item, dict):
                raise ValueError(f"baseline is missing workload: {platform}/{workload}")
            result[platform][workload] = {
                "native_median": float(item["native_median"]),
                "native_p95": float(item["native_p95"]),
                "wasm_median": float(item["wasm_median"]),
                "wasm_p95": float(item["wasm_p95"]),
            }
    return result


def baseline_toolchain(path: Path) -> tuple[str, str, str] | None:
    value = load_json(path)
    source = value.get("source")
    if not isinstance(source, dict):
        return None
    return toolchain_signature(source.get("toolchain"))


def lower_bound_allowances(path: Path | None) -> dict[tuple[str, str], float]:
    if path is None:
        return {}
    value = load_json(path)
    if value.get("schema_version") != 1 or value.get("confidence") != "95%":
        raise ValueError("Wasm lower-bound evidence must declare schema_version=1 and confidence=95%")
    entries = value.get("workloads")
    if not isinstance(entries, dict):
        raise ValueError("Wasm lower-bound evidence has no workloads")
    result: dict[tuple[str, str], float] = {}
    for key, item in entries.items():
        platform, separator, workload = key.partition("/")
        if not separator or platform not in PLATFORMS or workload not in WORKLOADS:
            raise ValueError(f"invalid Wasm lower-bound key: {key}")
        if not isinstance(item, dict) or int(item.get("batches", 0)) < 3:
            raise ValueError(f"Wasm lower-bound evidence needs three batches: {key}")
        lower = float(item.get("runtime_plus_package_lower_bound_ratio", 0))
        if lower <= 3.0:
            raise ValueError(f"Wasm lower-bound evidence does not exceed 3x: {key}")
        result[(platform, workload)] = 5.0
    return result


def check(
    reports: dict[str, list[Path]],
    mode: str,
    output: Path,
    baseline: Path | None = None,
    lower_bound: Path | None = None,
    regression: float = 1.05,
    expected_commit: str | None = None,
) -> dict[str, Any]:
    if mode not in {"pr", "strict"}:
        raise ValueError("mode must be pr or strict")
    required_batches = 1 if mode == "pr" else 3
    parsed = {
        platform: [extract_batch(load_json(path), path) for path in paths]
        for platform, paths in reports.items()
    }
    failures: list[str] = []
    if mode == "pr" and baseline is None:
        failures.append("PR mode requires --baseline accepted performance ratios")
    baseline_values = baseline_ratios(baseline) if baseline is not None else None
    allowances = lower_bound_allowances(lower_bound)
    platform_results: dict[str, Any] = {}
    toolchain_values = {
        toolchain_signature(batch["toolchain"])
        for batches in parsed.values()
        for batch in batches
    }
    if None in toolchain_values:
        failures.append("performance batch is missing a parseable MoonBit toolchain")
    if len(toolchain_values) > 1:
        failures.append("performance batches use different MoonBit toolchains")
    if mode == "pr" and baseline is not None:
        accepted_toolchain = baseline_toolchain(baseline)
        if accepted_toolchain is not None and toolchain_values != {accepted_toolchain}:
            failures.append(
                "PR performance batch toolchain differs from the accepted baseline: "
                f"{sorted(toolchain_values, key=str)} != {accepted_toolchain}"
            )
    for platform in PLATFORMS:
        batches = parsed[platform]
        if expected_commit is not None:
            for batch in batches:
                if batch["commit_sha"] != expected_commit:
                    failures.append(
                        f"{platform} report commit differs from exact head: {batch['commit_sha']}"
                    )
        for batch in batches:
            if batch["official_commit"] not in (None, OFFICIAL_COMMIT):
                failures.append(
                    f"{platform} report uses unexpected official commit: {batch['official_commit']}"
                )
        if len(batches) < required_batches:
            failures.append(f"{platform} has {len(batches)} batch(es), requires {required_batches}")
        workload_results: dict[str, Any] = {}
        if not batches:
            platform_results[platform] = {
                "batch_count": 0,
                "commit_shas": [],
                "toolchains": [],
                "workloads": {},
            }
            continue
        for workload in WORKLOADS:
            values: dict[str, Any] = {}
            for target in ("native", "wasm"):
                median_ratios = [batch["workloads"][workload][target]["median_ratio"] for batch in batches]
                p95_ratios = [batch["workloads"][workload][target]["p95_ratio"] for batch in batches]
                median_ratio = statistics.median(median_ratios)
                p95_ratio = statistics.median(p95_ratios)
                if target == "native":
                    median_limit, p95_limit = 1.10, 1.25
                elif workload == "startup":
                    median_limit, p95_limit = 2.0, 2.0
                else:
                    median_limit, p95_limit = 3.0, 3.0
                    if (platform, workload) in allowances:
                        median_limit = p95_limit = allowances[(platform, workload)]
                reasons: list[str] = []
                if mode == "strict":
                    if median_ratio > median_limit:
                        reasons.append(f"median {median_ratio:.3f}x > {median_limit:.3f}x")
                    if p95_ratio > p95_limit:
                        reasons.append(f"p95 {p95_ratio:.3f}x > {p95_limit:.3f}x")
                elif baseline_values is not None:
                    baseline_key = f"{target}_median"
                    baseline_p95_key = f"{target}_p95"
                    if median_ratio > baseline_values[platform][workload][baseline_key] * regression:
                        reasons.append(f"median regressed beyond {regression:.2f}x baseline")
                    if p95_ratio > baseline_values[platform][workload][baseline_p95_key] * regression:
                        reasons.append(f"p95 regressed beyond {regression:.2f}x baseline")
                if reasons:
                    failures.append(f"{platform}/{workload}/{target}: " + "; ".join(reasons))
                values[target] = {
                    "median_ratio": median_ratio,
                    "p95_ratio": p95_ratio,
                    "batch_median_ratios": median_ratios,
                    "batch_p95_ratios": p95_ratios,
                    "threshold": {"median": median_limit, "p95": p95_limit},
                    "status": "failed" if reasons else "passed",
                    "failure_reasons": reasons,
                }
            workload_results[workload] = values
        platform_results[platform] = {
            "batch_count": len(batches),
            "commit_shas": [batch["commit_sha"] for batch in batches],
            "toolchains": [batch["toolchain"] for batch in batches],
            "workloads": workload_results,
        }
    result = {
        "schema_version": SCHEMA_VERSION,
        "status": "passed" if not failures else "failed",
        "mode": mode,
        "required_batches": required_batches,
        "regression_limit": regression if mode == "pr" else None,
        "wasm_lower_bound_evidence": str(lower_bound) if lower_bound else None,
        "platforms": platform_results,
        "failures": failures,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("pr", "strict"), required=True)
    parser.add_argument("--report", action="append", default=[])
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--wasm-lower-bound", type=Path)
    parser.add_argument("--expected-commit")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = check(
        parse_assignments(args.report),
        args.mode,
        args.output.resolve(),
        args.baseline.resolve() if args.baseline else None,
        args.wasm_lower_bound.resolve() if args.wasm_lower_bound else None,
        expected_commit=args.expected_commit,
    )
    for failure in result["failures"]:
        print(f"performance gate: {failure}")
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise SystemExit(f"performance gate error: {error}")
