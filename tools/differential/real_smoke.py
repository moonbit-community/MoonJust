#!/usr/bin/env python3
"""Run the real differential smoke through the Python harness."""

from __future__ import annotations

import os
import platform
import subprocess
import sys
import tomllib
from pathlib import Path


def validate_manifest(manifest: Path) -> None:
    document = tomllib.loads(manifest.read_text(encoding="utf-8"))
    cases = document.get("case", [])
    if document.get("schema_version") != 3 or len(cases) != 182:
        raise SystemExit(f"differential manifest expected schema 3 and 182 cases, found {len(cases)}")
    seen: set[str] = set()
    allowed_areas = {"query-cli", "execution-context", "executor", "runtime-cache", "platform-compatibility"}
    for case in cases:
        case_id = case.get("id")
        if not isinstance(case_id, str) or case_id in seen:
            raise SystemExit(f"invalid or duplicate differential case id: {case_id}")
        seen.add(case_id)
        if case.get("status") not in {"match", "expected-difference"}:
            raise SystemExit(f"case {case_id} is not explicitly classified")
        if case.get("owner_area") not in allowed_areas:
            raise SystemExit(f"case {case_id} has an invalid owner area")
        if case.get("status") == "expected-difference" and case.get("allowed_difference", "none") == "none":
            raise SystemExit(f"case {case_id} has an unbounded expected difference")
        case_dir = manifest.parent / "cases" / case["directory"]
        if (case_dir / "expectation").read_text(encoding="utf-8").strip() != (
            "difference" if case["status"] == "expected-difference" else "match"
        ):
            raise SystemExit(f"case {case_id} expectation does not match manifest status")
        if (case_dir / "compat-id").read_text(encoding="utf-8").strip() != case_id:
            raise SystemExit(f"case {case_id} compat-id does not match manifest")


def build_metadata(repo: Path, output: Path) -> None:
    result = subprocess.run(
        [sys.executable, "tools/upstream/build_oracle.py"],
        cwd=repo,
        capture_output=True,
        text=True,
        check=True,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(result.stdout, encoding="utf-8")


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    manifest = repo / "tests/differential/cases.toml"
    validate_manifest(manifest)
    suffix = "just.exe" if platform.system() == "Windows" else "just"
    oracle = Path(os.environ.get("MOONJUST_ORACLE_CANDIDATE", str(repo / "_build/upstream/just-1.57.0/target/release" / suffix)))
    native = Path(os.environ.get("MOONJUST_NATIVE_CANDIDATE", str(repo / "_build/native/debug/build/cmd/just/just.exe")))
    wasm = Path(os.environ.get("MOONJUST_WASM_CANDIDATE", str(repo / "_build/wasm/debug/build/cmd/just/just.wasm")))
    oracle_was_missing = not oracle.is_file() and "MOONJUST_ORACLE_CANDIDATE" not in os.environ
    if oracle_was_missing:
        build_metadata(repo, repo / "_build/differential/oracle-metadata.txt")
    if not native.is_file() and "MOONJUST_NATIVE_CANDIDATE" not in os.environ:
        subprocess.run(["moon", "build", "--target", "native", "cmd/just"], cwd=repo, check=True)
    if not wasm.is_file() and "MOONJUST_WASM_CANDIDATE" not in os.environ:
        subprocess.run(["moon", "build", "--target", "wasm", "cmd/just"], cwd=repo, check=True)
    if not oracle.is_file() or not native.is_file() or not wasm.is_file():
        raise SystemExit("differential smoke artifacts are incomplete")
    metadata = repo / "_build/differential/oracle-metadata.txt"
    if "MOONJUST_ORACLE_CANDIDATE" not in os.environ and not oracle_was_missing:
        build_metadata(repo, metadata)
    else:
        metadata.parent.mkdir(parents=True, exist_ok=True)
        metadata.write_text(f"oracle={oracle}\n", encoding="utf-8")
    subprocess.run(
        [sys.executable, "tools/differential/run.py", "--upstream", str(oracle),
         "--candidate-native", str(native), "--candidate-wasm", str(wasm),
         "--wasm-policy", str(repo / "policies/execute.toml"),
         "--artifacts", str(repo / "_build/differential/real")],
        cwd=repo,
        check=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
