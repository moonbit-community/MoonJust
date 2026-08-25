#!/usr/bin/env python3
"""Validate and aggregate release evidence into one machine-readable record."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import platform
import subprocess
import sys
from collections import Counter
from pathlib import Path


SCHEMA_VERSION = 2
UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
REQUIRED_PLATFORMS = {"linux-x86_64", "macos-aarch64", "windows-x86_64"}
RELEASE_APPROVED_DIFFERENCES = {
    "JUST-1.57.0-2235": {
        "disposition": "unsupported",
        "tracking": "ADR-0019",
        "evidence": {
            "docs/adr/0019-direct-child-process-lifecycle.md",
            "docs/adr/0020-async-only-signal-semantics.md",
            "tools/upstream/run_official_harness.py",
        },
    },
}
PLATFORM_SYSTEMS = {
    "linux-x86_64": "Linux",
    "macos-aarch64": "Darwin",
    "windows-x86_64": "Windows",
}
COMPATIBILITY_DISPOSITIONS = {
    "exact",
    "diagnostic-exact",
    "diagnostic-semantic",
    "product-identity",
    "excluded-completion",
    "upstream-ignored",
    "not-applicable",
    "approved-difference",
    "failed",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def load_jsonl(path: Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid JSONL at {path}:{line_number}: {error}") from error
        if not isinstance(value, dict):
            raise ValueError(f"JSONL row is not an object at {path}:{line_number}")
        rows.append(value)
    return rows


def parse_assignment(value: str) -> tuple[str, Path]:
    name, separator, raw_path = value.partition("=")
    if not separator or not name or not raw_path:
        raise ValueError(f"expected NAME=PATH, observed {value!r}")
    return name, Path(raw_path).resolve()


def indexed_paths(
    values: list[str],
    label: str,
    failures: list[str] | None = None,
) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for value in values:
        name, path = parse_assignment(value)
        if name in result:
            raise ValueError(f"duplicate {label} record for {name}")
        if not path.is_file():
            message = f"{label} input is missing: {path}"
            if failures is None:
                raise ValueError(message)
            failures.append(message)
            continue
        result[name] = path
    return result


def artifact(path: Path) -> dict[str, object]:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}


def command_output(command: list[str]) -> str | None:
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except (OSError, subprocess.SubprocessError):
        return None
    return (result.stdout + result.stderr).strip()


def source_provenance(moonjust_commit: str, failures: list[str]) -> dict[str, object]:
    clean = subprocess.run(
        ["git", "diff", "--quiet"], check=False
    ).returncode == 0 and subprocess.run(
        ["git", "diff", "--cached", "--quiet"], check=False
    ).returncode == 0
    if not clean:
        failures.append("release evidence source tree is dirty")
    return {
        "moonjust_commit": moonjust_commit,
        "official_commit": UPSTREAM_COMMIT,
        "merge_base": command_output(["git", "merge-base", "HEAD", "main"]),
        "working_tree_clean": clean,
        "runner": {
            "os": platform.platform(),
            "python": platform.python_version(),
        },
    }


def moon_toolchain_identity(value: object) -> str | None:
    if not isinstance(value, str) or not value.strip():
        return None
    lines: list[str] = []
    for line in value.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        parts = stripped.split()
        if parts[0] in {"moon", "moonc", "moonrun"} and len(parts) > 1:
            if parts[-1].startswith(("/", "~")) or "\\" in parts[-1]:
                parts.pop()
            stripped = " ".join(parts)
        lines.append(stripped)
    return "\n".join(lines)


def coverage_metadata_summaries(
    paths: dict[str, Path],
    moonjust_commit: str,
    failures: list[str],
) -> dict[str, object]:
    expected = {"native", "wasm"}
    if set(paths) != expected:
        failures.append("coverage metadata must cover native and wasm exactly")
    values: dict[str, object] = {}
    for target, path in sorted(paths.items()):
        value = load_json(path)
        if value.get("schema_version") != 1:
            failures.append(f"coverage metadata schema changed for {target}")
        if value.get("target") != target or value.get("commit") != moonjust_commit:
            failures.append(f"coverage metadata source or target mismatch for {target}")
        sources = value.get("sources", [])
        traces = value.get("traces", [])
        if not isinstance(sources, list) or not sources:
            failures.append(f"coverage metadata has no sources for {target}")
        if not isinstance(traces, list) or not traces:
            failures.append(f"coverage metadata has no traces for {target}")
        identity = moon_toolchain_identity(value.get("moon"))
        if identity is None:
            failures.append(f"coverage MoonBit toolchain is missing for {target}")
        values[target] = {
            "path": str(path),
            "sha256": sha256(path),
            "toolchain": identity,
            "sources": len(sources) if isinstance(sources, list) else 0,
            "traces": len(traces) if isinstance(traces, list) else 0,
        }
    return values


def toolchain_summary(
    coverage_metadata: dict[str, object],
    performance: dict[str, object],
    sizes: dict[str, object],
    failures: list[str],
) -> dict[str, object]:
    sources: dict[str, str] = {}
    for target, entry in coverage_metadata.items():
        if isinstance(entry, dict) and isinstance(entry.get("toolchain"), str):
            sources[f"coverage/{target}"] = str(entry["toolchain"])
    performance_value = performance.get("summary", {})
    if isinstance(performance_value, dict) and isinstance(performance_value.get("measurements"), dict):
        performance_value = performance_value["measurements"].get("report", performance_value)
    if isinstance(performance_value, dict):
        identity = moon_toolchain_identity(performance_value.get("moon"))
        if identity is not None:
            sources["performance"] = identity
    for platform_name, entry in sizes.items():
        summary = entry.get("summary", {}) if isinstance(entry, dict) else {}
        if isinstance(summary, dict):
            identity = moon_toolchain_identity(summary.get("moon"))
            if identity is not None:
                sources[f"size/{platform_name}"] = identity
    identities = set(sources.values())
    if not sources:
        failures.append("release evidence contains no MoonBit toolchain fingerprints")
    elif len(identities) != 1:
        failures.append("infrastructure: MoonBit toolchain fingerprints differ across jobs")
    return {
        "identity": next(iter(identities)) if len(identities) == 1 else None,
        "sources": dict(sorted(sources.items())),
    }


def compatibility_summary(path: Path, failures: list[str]) -> dict[str, object]:
    rows = load_jsonl(path)
    dispositions = Counter(str(row.get("disposition")) for row in rows)
    invalid = sorted(set(dispositions) - COMPATIBILITY_DISPOSITIONS)
    if invalid:
        failures.append(f"compatibility report has invalid dispositions: {invalid!r}")
    if any(row.get("upstream_commit") != UPSTREAM_COMMIT for row in rows):
        failures.append("compatibility report is not pinned to the official commit")
    failed_rows = [row for row in rows if row.get("disposition") == "failed"]
    if failed_rows:
        failures.append(f"compatibility report has {len(failed_rows)} failed cases")
    denominator = sum(bool(row.get("compatibility_rate_denominator")) for row in rows)
    return {
        "path": str(path),
        "sha256": sha256(path),
        "rows": len(rows),
        "denominator": denominator,
        "dispositions": dict(sorted(dispositions.items())),
    }


def platform_evidence_summaries(
    paths: dict[str, Path],
    moonjust_commit: str,
    failures: list[str],
) -> dict[str, object]:
    if set(paths) != REQUIRED_PLATFORMS:
        failures.append("platform evidence does not cover all three release platforms")
    values: dict[str, object] = {}
    for name, path in sorted(paths.items()):
        value = load_json(path)
        if value.get("schema_version") != 2:
            failures.append(f"platform evidence schema changed for {name}")
        if value.get("commit_sha") != moonjust_commit:
            failures.append(f"platform evidence commit differs for {name}")
        if value.get("mode") != "compat" or value.get("status") != "passed":
            failures.append(f"platform evidence is not passing for {name}")
        host = value.get("host", {})
        if not isinstance(host, dict) or host.get("system") != PLATFORM_SYSTEMS.get(name):
            failures.append(f"platform evidence host differs for {name}")
        measurements = value.get("measurements", {})
        tasks = measurements.get("tasks", []) if isinstance(measurements, dict) else []
        task_status = {
            str(task.get("name")): task.get("status")
            for task in tasks
            if isinstance(task, dict)
        }
        for required in ("platform", "wasm-platform"):
            if task_status.get(required) != "passed":
                failures.append(f"platform evidence task {required} is not passing for {name}")
        values[name] = {
            "path": str(path),
            "sha256": sha256(path),
            "host": host,
            "tasks": dict(sorted(task_status.items())),
        }
    return values


def official_harness_summary(
    path: Path,
    moonjust_commit: str,
    failures: list[str],
) -> dict[str, object]:
    value = load_json(path)
    if value.get("schema_version") != SCHEMA_VERSION:
        failures.append("official harness evidence schema changed")
    if value.get("commit_sha") != moonjust_commit:
        failures.append("official harness evidence commit differs")
    if value.get("mode") != "compat" or value.get("status") != "passed":
        failures.append("official harness evidence is not passing")
    host = value.get("host", {})
    if (
        not isinstance(host, dict)
        or host.get("system") != PLATFORM_SYSTEMS["linux-x86_64"]
    ):
        failures.append("official harness evidence host differs from Linux")
    measurements = value.get("measurements", {})
    tasks = measurements.get("tasks", []) if isinstance(measurements, dict) else []
    task_status = {
        str(task.get("name")): task.get("status")
        for task in tasks
        if isinstance(task, dict)
    }
    if task_status.get("official-harness") != "passed":
        failures.append("official harness evidence task is not passing")
    return {
        "path": str(path),
        "sha256": sha256(path),
        "host": host,
        "tasks": dict(sorted(task_status.items())),
    }


def is_release_approved_difference(row: dict[str, object]) -> bool:
    rule = RELEASE_APPROVED_DIFFERENCES.get(str(row.get("id")))
    return (
        rule is not None
        and row.get("disposition") == rule["disposition"]
        and row.get("tracking") == rule["tracking"]
        and rule["evidence"] <= set(row.get("evidence", []))
    )


def test_map_summary(path: Path, failures: list[str]) -> dict[str, object]:
    rows = load_jsonl(path)
    dispositions = Counter(str(row.get("disposition")) for row in rows)
    compatibility = [row for row in rows if row.get("scope") == "compatibility"]
    approved_ids = {
        str(row.get("id"))
        for row in compatibility
        if is_release_approved_difference(row)
    }
    expected_ids = set(RELEASE_APPROVED_DIFFERENCES)
    if any(str(row.get("id")) in expected_ids for row in compatibility) and (
        approved_ids != expected_ids
    ):
        failures.append("release-approved compatibility differences drifted")
    incomplete = [
        row
        for row in compatibility
        if row.get("disposition") not in {"verified-differential", "verified-contract"}
        and not is_release_approved_difference(row)
    ]
    by_area = Counter(str(row.get("owner_area", "unknown")) for row in incomplete)
    by_disposition = Counter(
        str(row.get("disposition", "unknown")) for row in incomplete
    )
    if incomplete:
        breakdown = ", ".join(
            f"{area}={count}" for area, count in sorted(by_area.items())
        )
        failures.append(
            f"strict release evidence has {len(incomplete)} incomplete registrations "
            f"({breakdown})"
        )
    return {
        "path": str(path),
        "sha256": sha256(path),
        "rows": len(rows),
        "compatibility_rows": len(compatibility),
        "unverified": len(incomplete),
        "incomplete_by_area": dict(sorted(by_area.items())),
        "incomplete_by_disposition": dict(sorted(by_disposition.items())),
        "incomplete_registrations": [
            {
                "id": row.get("id"),
                "upstream_name": row.get("upstream_name"),
                "owner_area": row.get("owner_area"),
                "disposition": row.get("disposition"),
                "reason": row.get("reason"),
                "tracking": row.get("tracking"),
            }
            for row in incomplete
        ],
        "dispositions": dict(sorted(dispositions.items())),
    }


def contract_summary(
    path: Path,
    test_map: Path,
    failures: list[str],
) -> dict[str, object]:
    registrations = [
        row
        for row in load_jsonl(test_map)
        if row.get("disposition") == "verified-contract"
    ]
    executions = load_jsonl(path)
    expected = {
        (str(row["id"]), str(target))
        for row in registrations
        for target in row.get("targets", [])
    }
    actual = {
        (str(row.get("case_id")), str(row.get("target")))
        for row in executions
    }
    if len(actual) != len(executions):
        failures.append("contract results contain duplicate case/target executions")
    if actual != expected:
        failures.append("contract execution target matrix differs from the test map")
    registrations_by_id = {str(row["id"]): row for row in registrations}
    for execution in executions:
        case_id = str(execution.get("case_id"))
        registration = registrations_by_id.get(case_id)
        if execution.get("schema_version") not in {1, 2}:
            failures.append(f"contract result schema changed for {case_id}")
        if execution.get("passed") is not True:
            failures.append(f"contract execution failed for {case_id}")
        if execution.get("upstream_commit") != UPSTREAM_COMMIT:
            failures.append(f"contract source commit changed for {case_id}")
        if registration is None:
            continue
        if execution.get("upstream_name") != registration.get("upstream_name"):
            failures.append(f"contract upstream name changed for {case_id}")
        if execution.get("upstream_source") != registration.get("upstream_source"):
            failures.append(f"contract source provenance changed for {case_id}")
    return {
        "path": str(path),
        "sha256": sha256(path),
        "registrations": len(registrations),
        "executions": len(executions),
        "targets": dict(
            sorted(Counter(str(row.get("target")) for row in executions).items())
        ),
    }


def coverage_summary(path: Path, failures: list[str]) -> dict[str, object]:
    value = load_json(path)
    overall = value.get("overall", {})
    if not isinstance(overall, dict) or float(overall.get("rate", 0.0)) < 0.80:
        failures.append("overall coverage is below 80%")
    return {"path": str(path), "sha256": sha256(path), "summary": value}


def _validate_benchmark_samples(report: dict[str, object], failures: list[str], label: str) -> None:
    if report.get("status") != "passed":
        failures.append(f"{label} benchmark status is {report.get('status')!r}")
    cold_warm = report.get("cold_warm")
    if not isinstance(cold_warm, dict) or cold_warm.get("enabled") is not True:
        failures.append(f"{label} benchmark is missing cold/warm evidence")
        return
    if cold_warm.get("rounds") != 3 or cold_warm.get("warmups_per_round") != 5:
        failures.append(f"{label} benchmark cold/warm policy is incomplete")
    workloads = cold_warm.get("workloads")
    required_workloads = {"project-modules", "project-parameters", "project-execution"}
    if not isinstance(workloads, dict) or set(workloads) != required_workloads:
        failures.append(f"{label} benchmark workload inventory is incomplete")
        return
    for workload in sorted(required_workloads):
        entries = workloads[workload]
        for kind in ("official", "candidate-native", "candidate-wasm"):
            conditions = entries.get(kind) if isinstance(entries, dict) else None
            for condition in ("cold", "warm"):
                summary = conditions.get(condition) if isinstance(conditions, dict) else None
                if not isinstance(summary, dict) or summary.get("latency_samples") != 3:
                    failures.append(f"{label} benchmark samples are incomplete for {workload}/{kind}/{condition}")


def performance_summary(
    path: Path,
    failures: list[str],
    expected_commit: str | None = None,
) -> dict[str, object]:
    value = load_json(path)
    report = value
    if value.get("schema_version") == 2 and isinstance(value.get("measurements"), dict):
        nested = value["measurements"].get("report")
        if isinstance(nested, dict):
            report = nested
    if value.get("schema_version") not in {2, 3, 4}:
        failures.append("performance report schema changed")
    if expected_commit is not None:
        observed_commit = value.get("commit_sha", value.get("commit"))
        if observed_commit != expected_commit:
            failures.append("performance report commit differs from exact head")
    if isinstance(report.get("platform_reports"), dict):
        platform_reports = report.get("platform_reports", {})
        if not isinstance(platform_reports, dict) or set(platform_reports) != REQUIRED_PLATFORMS:
            failures.append("cloud performance report does not cover all release platforms")
        else:
            for platform_name in sorted(REQUIRED_PLATFORMS):
                entry = platform_reports.get(platform_name)
                nested = entry.get("report") if isinstance(entry, dict) else None
                if not isinstance(entry, dict) or entry.get("commit_sha") != expected_commit:
                    failures.append(f"cloud performance evidence has an invalid head for {platform_name}")
                if not isinstance(nested, dict):
                    failures.append(f"cloud performance report is missing for {platform_name}")
                    continue
                _validate_benchmark_samples(nested, failures, platform_name)
    else:
        _validate_benchmark_samples(report, failures, "performance")
    return {
        "path": str(path),
        "sha256": sha256(path),
        "mode": "report-only",
        "summary": value,
    }


def size_summaries(paths: dict[str, Path], failures: list[str]) -> dict[str, object]:
    if set(paths) != REQUIRED_PLATFORMS:
        failures.append(
            "size reports must cover exactly " + ", ".join(sorted(REQUIRED_PLATFORMS))
        )
    values: dict[str, object] = {}
    wasm_hashes: set[str] = set()
    for name, path in sorted(paths.items()):
        value = load_json(path)
        if value.get("platform") != name:
            failures.append(f"size report platform mismatch for {name}")
        if value.get("status") != "passed" or value.get("missing_baselines"):
            failures.append(f"size report is not complete and passing for {name}")
        wasm = value.get("wasm1", {})
        if isinstance(wasm, dict) and isinstance(wasm.get("sha256"), str):
            wasm_hashes.add(str(wasm["sha256"]))
        values[name] = {"path": str(path), "sha256": sha256(path), "summary": value}
    if len(wasm_hashes) != 1:
        failures.append("platform size reports do not reference one shared wasm artifact")
    return values


def build_proofs(
    paths: dict[str, Path],
    wasm_hash: str,
    moonjust_commit: str,
    sizes: dict[str, object],
    failures: list[str],
) -> dict[str, object]:
    if set(paths) != REQUIRED_PLATFORMS:
        failures.append(
            "build proofs must cover exactly " + ", ".join(sorted(REQUIRED_PLATFORMS))
        )
    values: dict[str, object] = {}
    for name, path in sorted(paths.items()):
        value = load_json(path)
        if value.get("platform") != name:
            failures.append(f"build proof platform mismatch for {name}")
        if value.get("schema_version") != 1 or value.get("commit") != moonjust_commit:
            failures.append(f"build proof source commit mismatch for {name}")
        if value.get("wasm_sha256") != wasm_hash:
            failures.append(f"build proof {name} does not reference the shared wasm hash")
        size = sizes.get(name, {})
        summary = size.get("summary", {}) if isinstance(size, dict) else {}
        native = summary.get("native", {}) if isinstance(summary, dict) else {}
        archive = summary.get("archive", {}) if isinstance(summary, dict) else {}
        if not isinstance(native, dict) or value.get("native_sha256") != native.get("sha256"):
            failures.append(f"build proof native hash mismatch for {name}")
        if not isinstance(archive, dict) or value.get("archive_sha256") != archive.get("sha256"):
            failures.append(f"build proof archive hash mismatch for {name}")
        values[name] = {"path": str(path), "sha256": sha256(path), "proof": value}
    return values


def repeatability_summaries(
    paths: dict[str, Path],
    moonjust_commit: str,
    native: dict[str, dict[str, object]],
    wasm: dict[str, object],
    sizes: dict[str, object],
    failures: list[str],
) -> dict[str, object]:
    expected_names = REQUIRED_PLATFORMS | {"wasm1"}
    if set(paths) != expected_names:
        failures.append("repeatability reports must cover three native platforms and wasm1")
    values: dict[str, object] = {}
    for name, path in sorted(paths.items()):
        value = load_json(path)
        if value.get("schema_version") != 1 or value.get("status") != "passed":
            failures.append(f"repeatability report is not passing for {name}")
        if value.get("commit") != moonjust_commit or value.get("platform") != name:
            failures.append(f"repeatability source or platform mismatch for {name}")
        pairs = value.get("pairs", {})
        if not isinstance(pairs, dict):
            failures.append(f"repeatability pairs are missing for {name}")
            pairs = {}
        expected_pairs = {"wasm1"} if name == "wasm1" else {"native", "archive"}
        if set(pairs) != expected_pairs:
            failures.append(f"repeatability pair inventory differs for {name}")
        if name == "wasm1":
            expected_hashes = {"wasm1": wasm.get("sha256")}
        else:
            size = sizes.get(name, {})
            summary = size.get("summary", {}) if isinstance(size, dict) else {}
            archive = summary.get("archive", {}) if isinstance(summary, dict) else {}
            expected_hashes = {
                "native": native.get(name, {}).get("sha256"),
                "archive": archive.get("sha256") if isinstance(archive, dict) else None,
            }
        for pair_name, expected_hash in expected_hashes.items():
            pair = pairs.get(pair_name, {})
            if not isinstance(pair, dict) or pair.get("sha256") != expected_hash:
                failures.append(f"repeatability hash mismatch for {name}/{pair_name}")
        values[name] = {"path": str(path), "sha256": sha256(path), "summary": value}
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-map", type=Path, required=True)
    parser.add_argument("--contract-results", type=Path, required=True)
    parser.add_argument("--compat-report", action="append", default=[])
    parser.add_argument("--platform-evidence", action="append", default=[])
    parser.add_argument("--official-evidence", action="append", default=[])
    parser.add_argument("--coverage", type=Path, required=True)
    parser.add_argument("--coverage-metadata", action="append", default=[])
    parser.add_argument("--performance", type=Path, required=True)
    parser.add_argument("--size-report", action="append", default=[])
    parser.add_argument("--native", action="append", default=[])
    parser.add_argument("--wasm", type=Path, required=True)
    parser.add_argument("--build-proof", action="append", default=[])
    parser.add_argument("--repeatability", action="append", default=[])
    parser.add_argument("--mode", choices=("pr", "release"), default="release")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    failures: list[str] = []
    compatibility_paths = indexed_paths(args.compat_report, "compatibility", failures)
    platform_evidence_paths = indexed_paths(
        args.platform_evidence, "platform evidence", failures
    )
    official_evidence_paths = indexed_paths(
        args.official_evidence, "official harness evidence", failures
    )
    coverage_metadata_paths = indexed_paths(
        args.coverage_metadata, "coverage metadata", failures
    )
    size_paths = indexed_paths(args.size_report, "size", failures)
    native_paths = indexed_paths(args.native, "native", failures)
    proof_paths = indexed_paths(args.build_proof, "build proof", failures)
    repeatability_paths = indexed_paths(args.repeatability, "repeatability", failures)
    for path in (
        args.test_map,
        args.contract_results,
        args.coverage,
        args.performance,
        args.wasm,
    ):
        if not path.is_file():
            failures.append(f"release evidence input is missing: {path}")

    if set(compatibility_paths) != {"linux-x86_64"}:
        failures.append("official compatibility report must come from Linux exactly once")
    if args.mode == "release" and set(official_evidence_paths) != {"linux-x86_64"}:
        failures.append("official harness evidence must come from Linux exactly once")
    if set(native_paths) != REQUIRED_PLATFORMS:
        failures.append("native artifacts do not cover all three release platforms")
    native = {name: artifact(path) for name, path in sorted(native_paths.items())}
    wasm = artifact(args.wasm) if args.wasm.is_file() else {"path": str(args.wasm)}
    moonjust_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], check=True, capture_output=True, text=True
    ).stdout.strip()
    compatibility = {
        "official": (
            compatibility_summary(compatibility_paths["linux-x86_64"], failures)
            if "linux-x86_64" in compatibility_paths
            else {"missing": True}
        ),
        "official_harness": (
            official_harness_summary(
                official_evidence_paths["linux-x86_64"], moonjust_commit, failures
            )
            if "linux-x86_64" in official_evidence_paths
            else {"missing": True}
        ),
        "platforms": platform_evidence_summaries(
            platform_evidence_paths, moonjust_commit, failures
        ),
    }
    sizes = size_summaries(size_paths, failures)
    coverage_metadata = coverage_metadata_summaries(
        coverage_metadata_paths, moonjust_commit, failures
    )
    performance = (
        performance_summary(args.performance, failures, expected_commit=moonjust_commit)
        if args.performance.is_file()
        else {"path": str(args.performance), "missing": True}
    )
    missing_inputs = sorted(
        failure for failure in failures if " input is missing:" in failure
    )
    status = (
        "missing"
        if missing_inputs
        else "failed"
        if failures
        else "passed"
    )
    record = {
        "schema_version": SCHEMA_VERSION,
        "mode": args.mode,
        "status": status,
        "moonjust_commit": moonjust_commit,
        "official": {"version": "1.57.0", "commit": UPSTREAM_COMMIT},
        "generated_on": {"os": platform.platform(), "python": platform.python_version()},
        "provenance": source_provenance(moonjust_commit, failures),
        "test_map": (
            test_map_summary(args.test_map, failures)
            if args.test_map.is_file()
            else {"path": str(args.test_map), "missing": True}
        ),
        "contracts": (
            contract_summary(args.contract_results, args.test_map, failures)
            if args.contract_results.is_file() and args.test_map.is_file()
            else {"path": str(args.contract_results), "missing": True}
        ),
        "compatibility": compatibility,
        "coverage": (
            coverage_summary(args.coverage, failures)
            if args.coverage.is_file()
            else {"path": str(args.coverage), "missing": True}
        ),
        "coverage_metadata": coverage_metadata,
        "performance": performance,
        "size": sizes,
        "toolchain": toolchain_summary(
            coverage_metadata, performance, sizes, failures
        ),
        "artifacts": {"native": native, "wasm1": wasm},
        "build_proofs": build_proofs(
            proof_paths, str(wasm.get("sha256", "")), moonjust_commit, sizes, failures
        ),
        "repeatability": repeatability_summaries(
            repeatability_paths, moonjust_commit, native, wasm, sizes, failures
        ),
        "missing_inputs": missing_inputs,
    }
    # Validators append failures while the record is assembled.
    if any("infrastructure" in failure for failure in failures):
        record["status"] = "infrastructure-invalid"
    elif missing_inputs:
        record["status"] = "missing"
    else:
        record["status"] = "failed" if failures else "passed"
    record["failures"] = failures
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for failure in failures:
        print(f"release evidence: {failure}", file=sys.stderr)
    print(f"release evidence written to {args.output}")
    return 1 if args.strict and failures else 0


def write_fatal_record(error: Exception) -> None:
    try:
        index = sys.argv.index("--output")
        output = Path(sys.argv[index + 1])
    except (ValueError, IndexError):
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "schema_version": SCHEMA_VERSION,
        "status": "failed",
        "official": {"version": "1.57.0", "commit": UPSTREAM_COMMIT},
        "failures": [f"release evidence input error: {error}"],
    }
    output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError, subprocess.SubprocessError) as error:
        write_fatal_record(error)
        print(f"release evidence error: {error}", file=sys.stderr)
        raise SystemExit(2)
