#!/usr/bin/env python3
"""Validate and aggregate release evidence into one machine-readable record."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import subprocess
import sys
from collections import Counter
from pathlib import Path


SCHEMA_VERSION = 1
UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
REQUIRED_PLATFORMS = {"linux-x86_64", "macos-aarch64", "windows-x86_64"}
REQUIRED_COVERAGE_AREAS = {
    "lexer",
    "parser",
    "loader",
    "semantic",
    "executor",
    "runtime",
    "host_process",
}
COMPATIBILITY_DISPOSITIONS = {
    "exact",
    "diagnostic-exact",
    "diagnostic-semantic",
    "product-identity",
    "excluded-completion",
    "upstream-ignored",
    "not-applicable",
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


def indexed_paths(values: list[str], label: str) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for value in values:
        name, path = parse_assignment(value)
        if name in result:
            raise ValueError(f"duplicate {label} record for {name}")
        if not path.is_file():
            raise ValueError(f"{label} input is missing: {path}")
        result[name] = path
    return result


def artifact(path: Path) -> dict[str, object]:
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}


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


def test_map_summary(path: Path, failures: list[str]) -> dict[str, object]:
    rows = load_jsonl(path)
    dispositions = Counter(str(row.get("disposition")) for row in rows)
    compatibility = [row for row in rows if row.get("scope") == "compatibility"]
    incomplete = [
        row
        for row in compatibility
        if row.get("disposition") not in {"verified-differential", "verified-contract"}
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
        if execution.get("schema_version") != 1:
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
    changed = value.get("changed", {})
    packages = value.get("packages", {})
    if not isinstance(overall, dict) or float(overall.get("rate", 0.0)) < 0.80:
        failures.append("overall coverage is below 80%")
    if isinstance(changed, dict) and int(changed.get("valid", 0)) > 0 and float(changed.get("rate", 0.0)) < 0.90:
        failures.append("changed-line coverage is below 90%")
    if not isinstance(packages, dict):
        failures.append("coverage package report is missing")
    else:
        for area in sorted(REQUIRED_COVERAGE_AREAS):
            entry = packages.get(area, {})
            if not isinstance(entry, dict) or float(entry.get("rate", 0.0)) < 0.85:
                failures.append(f"{area} coverage is below 85%")
    return {"path": str(path), "sha256": sha256(path), "summary": value}


def performance_summary(path: Path, failures: list[str]) -> dict[str, object]:
    value = load_json(path)
    configuration = value.get("configuration", {})
    machine = value.get("machine", {})
    if value.get("status") != "passed":
        failures.append(f"authoritative performance status is {value.get('status')!r}")
    if not isinstance(configuration, dict) or configuration.get("authoritative") is not True:
        failures.append("performance report is not authoritative")
    if not isinstance(machine, dict) or machine.get("system") != "Linux" or machine.get("machine") not in {"x86_64", "AMD64"}:
        failures.append("performance report is not from Linux x86_64")
    return {"path": str(path), "sha256": sha256(path), "summary": value}


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
    parser.add_argument("--coverage", type=Path, required=True)
    parser.add_argument("--performance", type=Path, required=True)
    parser.add_argument("--size-report", action="append", default=[])
    parser.add_argument("--native", action="append", default=[])
    parser.add_argument("--wasm", type=Path, required=True)
    parser.add_argument("--build-proof", action="append", default=[])
    parser.add_argument("--repeatability", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    compatibility_paths = indexed_paths(args.compat_report, "compatibility")
    size_paths = indexed_paths(args.size_report, "size")
    native_paths = indexed_paths(args.native, "native")
    proof_paths = indexed_paths(args.build_proof, "build proof")
    repeatability_paths = indexed_paths(args.repeatability, "repeatability")
    for path in (
        args.test_map,
        args.contract_results,
        args.coverage,
        args.performance,
        args.wasm,
    ):
        if not path.is_file():
            raise ValueError(f"release evidence input is missing: {path}")

    failures: list[str] = []
    if set(compatibility_paths) != REQUIRED_PLATFORMS:
        failures.append("compatibility reports do not cover all three release platforms")
    compatibility = {
        name: compatibility_summary(path, failures)
        for name, path in sorted(compatibility_paths.items())
    }
    if set(native_paths) != REQUIRED_PLATFORMS:
        failures.append("native artifacts do not cover all three release platforms")
    native = {name: artifact(path) for name, path in sorted(native_paths.items())}
    wasm = artifact(args.wasm)
    moonjust_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], check=True, capture_output=True, text=True
    ).stdout.strip()
    sizes = size_summaries(size_paths, failures)
    record = {
        "schema_version": SCHEMA_VERSION,
        "status": "failed" if failures else "passed",
        "moonjust_commit": moonjust_commit,
        "official": {"version": "1.57.0", "commit": UPSTREAM_COMMIT},
        "generated_on": {"os": platform.platform(), "python": platform.python_version()},
        "test_map": test_map_summary(args.test_map, failures),
        "contracts": contract_summary(args.contract_results, args.test_map, failures),
        "compatibility": compatibility,
        "coverage": coverage_summary(args.coverage, failures),
        "performance": performance_summary(args.performance, failures),
        "size": sizes,
        "artifacts": {"native": native, "wasm1": wasm},
        "build_proofs": build_proofs(
            proof_paths, str(wasm["sha256"]), moonjust_commit, sizes, failures
        ),
        "repeatability": repeatability_summaries(
            repeatability_paths, moonjust_commit, native, wasm, sizes, failures
        ),
    }
    # Validators append failures while the record is assembled.
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
