#!/usr/bin/env python3
"""Audit one legacy differential case before changing its expected status."""

from __future__ import annotations

import argparse
import base64
import hashlib
import importlib.util
import json
import re
import sys
import subprocess
import tomllib
from difflib import unified_diff
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RUN_PATH = ROOT / "tools/differential/run.py"
SPEC = importlib.util.spec_from_file_location("moonjust_differential_run", RUN_PATH)
assert SPEC is not None and SPEC.loader is not None
RUN = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = RUN
SPEC.loader.exec_module(RUN)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fixture_hash(path: Path) -> str:
    digest = hashlib.sha256()
    for child in sorted(path.rglob("*"), key=lambda item: item.relative_to(path).as_posix()):
        if child.is_file():
            digest.update(child.relative_to(path).as_posix().encode())
            digest.update(b"\0")
            digest.update(child.read_bytes())
            digest.update(b"\0")
    return digest.hexdigest()


def metadata() -> dict[str, object]:
    path = ROOT / "_build/differential/oracle-metadata.txt"
    result: dict[str, object] = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            key, separator, value = line.partition("=")
            if separator:
                result[key] = value
    return result


def diff_bytes(left: bytes, right: bytes, left_name: str, right_name: str) -> str:
    left_text = left.decode("utf-8", errors="replace").splitlines()
    right_text = right.decode("utf-8", errors="replace").splitlines()
    return "\n".join(
        unified_diff(left_text, right_text, fromfile=left_name, tofile=right_name, lineterm="")
    )


def replace_single_case(manifest: Path, case_id: str) -> None:
    original = manifest.read_text(encoding="utf-8")
    blocks = list(re.finditer(r"(?ms)^\[\[case\]\]\n.*?(?=^\[\[case\]\]|\Z)", original))
    matches = []
    for match in blocks:
        block = match.group(0)
        parsed = tomllib.loads("schema_version = 3\n" + block)
        cases = parsed.get("case", [])
        if len(cases) == 1 and cases[0].get("id") == case_id:
            matches.append((match, block))
    if len(matches) != 1:
        raise ValueError(f"expected one manifest case {case_id}, found {len(matches)}")
    match, block = matches[0]
    parsed = tomllib.loads("schema_version = 3\n" + block)["case"][0]
    if parsed.get("status") != "expected-difference":
        raise ValueError(f"{case_id} is not currently expected-difference")
    updated = re.sub(r'(?m)^(status\s*=\s*)"[^"]+"$', r'\1"match"', block, count=1)
    updated = re.sub(r'(?m)^(allowed_difference\s*=\s*)"[^"]+"$', r'\1"none"', updated, count=1)
    if updated == block or 'status = "match"' not in updated or 'allowed_difference = "none"' not in updated:
        raise ValueError(f"{case_id} manifest block has an unexpected schema")
    rewritten = original[: match.start()] + updated + original[match.end() :]
    if rewritten.count('id = "' + case_id + '"') != 1:
        raise ValueError(f"single-case rewrite changed manifest identity for {case_id}")
    manifest.write_text(rewritten, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--candidate-native", type=Path, required=True)
    parser.add_argument("--candidate-wasm", type=Path)
    parser.add_argument("--wasm-policy", type=Path)
    parser.add_argument("--manifest", type=Path, default=ROOT / "tests/differential/cases.toml")
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.candidate_wasm is not None and args.wasm_policy is None:
        raise ValueError("--wasm-policy is required with --candidate-wasm")
    cases = RUN.load_cases(args.manifest.resolve())
    selected = [case for case in cases if case.case_id == args.case]
    if len(selected) != 1:
        raise ValueError(f"unknown or duplicate differential case: {args.case}")
    case = selected[0]
    case_dir = (args.cases or args.manifest.parent / "cases").resolve() / case.directory
    artifacts_root = (args.artifacts or ROOT / "_build/differential-audit").resolve()
    artifacts_root.mkdir(parents=True, exist_ok=True)
    artifact_dir = artifacts_root / case.directory
    if artifact_dir.exists():
        RUN.remove_tree(artifact_dir)
    artifact_dir.mkdir(parents=True)
    commands = [
        RUN.Command("upstream", (str(args.upstream.resolve()),)),
        RUN.Command("native", (str(args.candidate_native.resolve()),)),
    ]
    if args.candidate_wasm is not None:
        commands.append(
            RUN.Command(
                "wasm",
                (
                    "moonrun",
                    "--policy",
                    str(args.wasm_policy.resolve()),
                    str(args.candidate_wasm.resolve()),
                ),
            )
        )
    results = {
        command.name: RUN.run_side(command, case, case_dir, artifact_dir)
        for command in commands
    }
    observations = {
        command.name: sorted(
            RUN.compare_side(
                case,
                results["upstream"],
                results[command.name],
                command.name,
                artifact_dir,
            )
        )
        for command in commands[1:]
    }
    matched = all(not fields for fields in observations.values())
    record = {
        "schema_version": 1,
        "case_id": case.case_id,
        "directory": case.directory,
        "expected_status": case.expectation,
        "observed_match": matched,
        "observed_fields": observations,
        "official": {
            "binary_sha256": sha256(args.upstream.resolve()),
            "metadata": metadata(),
            "upstream_tests": list(case.upstream_tests),
        },
        "fixture_sha256": fixture_hash(case_dir),
        "artifacts": str(artifact_dir),
        "raw": {
            command: {
                field: base64.b64encode(value).decode("ascii")
                for field, value in values.items()
            }
            for command, values in results.items()
        },
    }
    for candidate, fields in observations.items():
        for field in fields:
            record.setdefault("diffs", {})[f"{candidate}.{field}"] = diff_bytes(
                results["upstream"][field], results[candidate][field], "official", candidate
            )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(record, indent=2, sort_keys=True))
    if args.apply:
        if not matched:
            raise ValueError(f"refusing to apply {case.case_id}: candidates still differ")
        replace_single_case(args.manifest.resolve(), case.case_id)
        expectation = case_dir / "expectation"
        if expectation.read_text(encoding="utf-8").strip() != "difference":
            raise ValueError(f"{case.case_id} expectation fixture is not difference")
        expectation.write_text("match\n", encoding="utf-8")
        print(f"applied one audited match: {case.case_id}")
    return 0 if matched else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, tomllib.TOMLDecodeError, subprocess.SubprocessError) as error:
        print(f"oracle audit error: {error}", file=sys.stderr)
        raise SystemExit(2)
