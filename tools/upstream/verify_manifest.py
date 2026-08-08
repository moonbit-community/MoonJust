#!/usr/bin/env python3
"""Validate compatibility manifests and exact selected MoonBit test counts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path


EXPECTED_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
EXPECTED_REGISTRATIONS = 2417
EXPECTED_LEXER_REGISTRATIONS = 93
EXPECTED_TEST_LIST_SHA256 = "34773c9c59398fe3ac490aa7239b3c33a7b615159ff59b1e85ddef5e802381d9"


def root() -> Path:
    return Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise ValueError(message)


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def load(path: Path) -> dict:
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as error:
        fail(f"cannot parse {path}: {error}")


def selected_tests(target: str, path: str | None = None) -> int:
    command = ["moon", "test", "--target", target]
    if path is not None:
        command.append(path)
    command.append("--outline")
    result = subprocess.run(
        command,
        cwd=root(),
        check=True,
        capture_output=True,
        text=True,
    )
    return sum(
        1
        for line in result.stdout.splitlines()
        if re.match(r"^\s*\d+\.\s+", line)
    )


def validate_test_anchor(
    repo: Path,
    row_id: str,
    anchor: object,
    source_cache: dict[str, str],
) -> None:
    expect(isinstance(anchor, dict), f"{row_id} has no executable test anchor")
    expect(set(anchor) == {"suite", "test_name"}, f"{row_id} has an invalid test anchor schema")
    suite = anchor["suite"]
    test_name = anchor["test_name"]
    expect(isinstance(suite, str) and suite, f"{row_id} has no test suite path")
    expect(isinstance(test_name, str) and test_name, f"{row_id} has no test name")
    if suite not in source_cache:
        path = repo / suite
        expect(path.is_file(), f"{row_id} test suite is missing: {suite}")
        source_cache[suite] = path.read_text(encoding="utf-8")
    declaration = re.compile(
        rf'^\s*test\s+"{re.escape(test_name)}"\s*\{{',
        re.MULTILINE,
    )
    expect(
        declaration.search(source_cache[suite]) is not None,
        f"{row_id} test declaration is missing: {suite}::{test_name}",
    )


def validate_map() -> None:
    repo = root()
    test_list = repo / "tests/upstream/just-1.57.0/test-list.txt"
    test_map = repo / "tests/upstream/just-1.57.0/test-map.jsonl"
    raw_list = test_list.read_bytes()
    expect(hashlib.sha256(raw_list).hexdigest() == EXPECTED_TEST_LIST_SHA256, "upstream test-list digest changed")
    names = raw_list.decode("utf-8").splitlines()
    expect(len(names) == EXPECTED_REGISTRATIONS, "upstream registration count changed")
    rows = [json.loads(line) for line in test_map.read_text(encoding="utf-8").splitlines()]
    expect(len(rows) == len(names), "upstream mapping row count does not match registrations")
    source_cache: dict[str, str] = {}
    for index, (row, name) in enumerate(zip(rows, names), start=1):
        expect(row["id"] == f"JUST-1.57.0-{index:04d}", f"invalid mapping id at row {index}")
        expect(row["upstream_name"] == name, f"mapping mismatch at row {index}")
        expect(row["owner_phase"] in range(2, 11), f"missing owner phase at row {index}")
        expect(row["tier"] in {"A", "B", "W", "X"}, f"invalid tier at row {index}")
        expect(row["tracking"], f"missing tracking owner at row {index}")
        for evidence in row["evidence"]:
            expect((repo / evidence).exists(), f"missing evidence {evidence} at row {index}")
        if row["owner_phase"] in {3, 4, 5, 6} and row["disposition"] == "covered-by":
            validate_test_anchor(repo, row["id"], row.get("test_anchor"), source_cache)
            expect(row["test_anchor"]["suite"] == row["evidence"][1], f"{row['id']} anchor suite differs from evidence")
        if row["owner_phase"] in {3, 4, 5, 6} and row["disposition"] == "covered-by":
            expect(row["disposition"] == "covered-by", f"Phase {row['owner_phase']} row {index} is not executable")
            expect(row["targets"] == ["native", "wasm1"], f"Phase {row['owner_phase']} row {index} target matrix is incomplete")

    lexer_names = [name for name in names if name.startswith("lexer::tests::")]
    expect(len(lexer_names) == EXPECTED_LEXER_REGISTRATIONS, "lexer registration count changed")
    phase2_rows = [row for row in rows if row["owner_phase"] == 2]
    expect(len(phase2_rows) == EXPECTED_LEXER_REGISTRATIONS, "Phase 2 mapping count changed")
    expect(
        all(row["disposition"] in {"covered-by", "not-applicable"} for row in phase2_rows),
        "Phase 2 contains an unclassified upstream registration",
    )
    for phase in (3, 4, 5, 6):
        cases = repo / f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl"
        rows_for_phase = [
            row
            for row in rows
            if row["owner_phase"] == phase and row["disposition"] == "covered-by"
        ]
        case_rows = [json.loads(line) for line in cases.read_text(encoding="utf-8").splitlines()]
        expect(len(case_rows) == len(rows_for_phase), f"Phase {phase} case manifest count changed")
        expected_by_id = {row["id"]: row for row in rows_for_phase}
        for case in case_rows:
            expect(case["disposition"] == "covered-by", f"Phase {phase} has non-executable cases")
            expected = expected_by_id.get(case.get("case_id"))
            expect(expected is not None, f"Phase {phase} case has an unknown id")
            expect(case.get("test_anchor") == expected.get("test_anchor"), f"Phase {phase} case anchor differs from test map")


def validate_differential_cases() -> None:
    repo = root()
    manifest = load(repo / "tests/differential/cases.toml")
    cases = manifest.get("case", [])
    expect(len(cases) == 10, "differential case count changed")
    seen = set()
    for case in cases:
        case_id = case["id"]
        expect(case_id not in seen, f"duplicate differential case {case_id}")
        seen.add(case_id)
        status = case["status"]
        expect(status in {"match", "expected-difference"}, f"case {case_id} is not classified")
        expect(case["owner_phase"] >= 6, f"case {case_id} is assigned to Phase 0-5")
        case_dir = repo / "tests/differential/cases" / case["directory"]
        expect((case_dir / "expectation").exists(), f"case {case_id} lacks expectation")
        expected = "match" if status == "match" else "difference"
        expect(
            (case_dir / "expectation").read_text(encoding="utf-8").strip() == expected,
            f"case {case_id} expectation differs from its manifest status",
        )
        expect((case_dir / "compat-id").read_text(encoding="utf-8").strip() == case_id, f"case {case_id} id mismatch")


def validate_builtins(manifest: dict) -> None:
    repo = root()
    subprocess.run(
        [sys.executable, str(repo / "tools/upstream/builtin_manifest.py"), "--check"],
        cwd=repo,
        check=True,
    )
    registry = manifest["registry"]
    path = repo / registry["typed_manifest"]
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    names = registry["canonical"]
    expect(len(rows) == 83, "typed builtin manifest count changed")
    expect([row["name"] for row in rows] == names, "typed builtin order differs from canonical inventory")
    for index, row in enumerate(rows, start=1):
        expect(row["schema_version"] == 1, f"builtin row {index} schema changed")
        expect(row["index"] == index, f"builtin row {index} index changed")
        expect(row["min_arguments"] >= 0, f"builtin row {index} has invalid minimum arity")
        maximum = row["max_arguments"]
        expect(maximum is None or maximum >= row["min_arguments"], f"builtin row {index} has invalid maximum arity")
        expect(row["purity"] in {"pure", "effect"}, f"builtin row {index} has invalid purity")
        expect((row["purity"] == "effect") == bool(row["capabilities"]), f"builtin row {index} purity/capability mismatch")
        expect(row["targets"] == ["native", "wasm1"], f"builtin row {index} target matrix incomplete")
        expect(row["tracking"] == f"MJ-BUILTIN-{index:03d}", f"builtin row {index} tracking id changed")
        for alias in row["aliases"]:
            expect(alias.endswith("_dir") or alias.endswith("_dir_native"), f"builtin row {index} has invalid alias")
        for evidence in row["evidence"]:
            expect((repo / evidence).exists(), f"builtin row {index} lacks evidence {evidence}")
    oracle = repo / "tests/upstream/just-1.57.0/phase-5-oracle.jsonl"
    oracle_rows = [json.loads(line) for line in oracle.read_text(encoding="utf-8").splitlines()]
    expect(len(oracle_rows) == 20, "Phase 5 Rust oracle count changed")
    expect(len({row["id"] for row in oracle_rows}) == 20, "Phase 5 Rust oracle ids are not unique")
    expect(all(row["schema_version"] == 1 for row in oracle_rows), "Phase 5 Rust oracle schema changed")
    expect(sum(row["id"].startswith("MJ-P5-SEMVER-") for row in oracle_rows) == 16, "Phase 5 SemVer oracle count changed")
    expect(sum(row["id"].startswith("MJ-P5-REGEX-") for row in oracle_rows) == 4, "Phase 5 regexp oracle count changed")
    for row in oracle_rows:
        expect(row["builtin"] in {"semver_matches", "replace_regex"}, f"invalid Phase 5 oracle builtin {row['builtin']}")
        expect(isinstance(row["arguments"], list), f"Phase 5 oracle {row['id']} arguments are not structured")
        expect(("expected" in row) != ("expected_error" in row), f"Phase 5 oracle {row['id']} has an ambiguous outcome")


def validate() -> None:
    repo = root()
    upstream = load(repo / "compat/just-1.57.0.toml")
    expect(upstream["upstream"]["commit"] == EXPECTED_COMMIT, "upstream commit changed")
    expect(upstream["test_inventory"]["registrations"] == EXPECTED_REGISTRATIONS, "registration count changed")
    expect(upstream["test_inventory"]["mapping"] == "tests/upstream/just-1.57.0/test-map.jsonl", "mapping path is not pinned")
    validate_map()
    validate_differential_cases()

    cli = load(repo / "compat/cli-options.toml")
    expect(len(cli["option"]) == 50, "CLI option inventory changed")
    expect(len(cli["command"]) == 19, "CLI command inventory changed")
    cli_entries = cli["option"] + cli["command"]
    expect(len({entry["name"] for entry in cli_entries}) == 69, "CLI inventory contains duplicates")
    expect(
        all(entry["status"] in {"planned", "implemented", "excluded"} for entry in cli_entries),
        "CLI inventory contains an invalid status",
    )
    expect(sum(entry["status"] == "implemented" for entry in cli["option"]) == 20, "implemented CLI option count changed")
    expect(sum(entry["status"] == "implemented" for entry in cli["command"]) == 11, "Phase 6 implemented command count changed")

    builtins = load(repo / "compat/builtins.toml")
    expect(builtins["registry"]["canonical_count"] == 83, "builtin count changed")
    expect(len(builtins["registry"]["canonical"]) == 83, "builtin inventory length changed")
    expect(len(set(builtins["registry"]["canonical"])) == 83, "builtin inventory contains duplicates")
    validate_builtins(builtins)

    phase1 = load(repo / "compat/phase-1.toml")
    contracts1 = phase1["contract"]
    expect(len(contracts1) == 5, "Phase 1 contract count changed")
    expect(
        all(c["status"] == "implemented" and c["native"] == "pass" and c["wasm1"] == "pass" for c in contracts1),
        "Phase 1 contract evidence is incomplete",
    )
    phase1_expected = {c["package"]: c["black_box_tests"] for c in contracts1}
    for target in ("native", "wasm"):
        for package, expected in phase1_expected.items():
            expect(
                selected_tests(target, package) == expected,
                f"{target} {package} test outline count changed",
            )

    phase2 = load(repo / "compat/phase-2.toml")
    inventory = phase2["upstream_lexer_inventory"]
    expect(inventory["registrations"] == EXPECTED_LEXER_REGISTRATIONS, "lexer registration count changed")
    expect(len(phase2["contract"]) == 5, "Phase 2 contract count changed")
    expect(
        all(c["status"] == "implemented" and c["native"] == "pass" and c["wasm1"] == "pass" for c in phase2["contract"]),
        "Phase 2 contract evidence is incomplete",
    )
    expect(inventory["random_inputs"] == 100000, "lexer hardening budget changed")
    expect(inventory["adapted_success_cases"] == 16, "lexer success-oracle count changed")
    expect(inventory["adapted_error_cases"] == 5, "lexer error-oracle count changed")
    expected_lexer_tests = sum(c["black_box_tests"] for c in phase2["contract"])
    for target in ("native", "wasm"):
        expect(selected_tests(target, "src/lexer") == expected_lexer_tests, f"{target} lexer test outline count changed")

    for phase in (3, 4, 5, 6):
        manifest = load(repo / f"compat/phase-{phase}.toml")
        expect(manifest["status"] == "implemented", f"Phase {phase} status is not implemented")
        if phase == 6:
            expect(
                manifest["plan_exit"] in {"pending-remote-ci-and-audit", "passed"},
                "Phase 6 exit has an invalid state",
            )
            expect(manifest["evidence"]["native_tests"] == 134, "Phase 6 Native evidence count changed")
            expect(manifest["evidence"]["wasm_tests"] == 133, "Phase 6 wasm evidence count changed")
        else:
            expect(manifest["plan_exit"] == "passed", f"Phase {phase} exit is not passed")
        corpus = load(repo / f"tests/upstream/just-1.57.0/phase-{phase}.toml")
        expect(corpus["upstream_commit"] == EXPECTED_COMMIT, f"Phase {phase} corpus commit changed")
        expect(corpus["license"] == "CC0-1.0", f"Phase {phase} corpus license changed")
        if phase == 6:
            phase6_rows = [
                json.loads(line)
                for line in (
                    repo / "tests/upstream/just-1.57.0/test-map.jsonl"
                ).read_text(encoding="utf-8").splitlines()
                if json.loads(line)["owner_phase"] == 6
            ]
            expect(
                corpus["covered_registrations"] == sum(
                    row["disposition"] == "covered-by" for row in phase6_rows
                ),
                "Phase 6 covered registration count changed",
            )
            expect(
                corpus["excluded_registrations"] == sum(
                    row["disposition"] in {"excluded-completion", "not-applicable"}
                    for row in phase6_rows
                ),
                "Phase 6 excluded registration count changed",
            )

    policy = load(repo / "policies/inspect.toml")
    expect(policy["fs"]["write"] == [], "Phase 6 inspect policy grants filesystem writes")
    expect(policy["process"]["spawn"] is False, "Phase 6 inspect policy grants process spawn")
    expect(policy["net"] == {"dns": [], "connect": [], "bind": []}, "Phase 6 inspect policy grants network access")
    wasm_interface = (repo / "src/host_wasm/pkg.generated.mbti").read_text(encoding="utf-8")
    expect("HostProcess" not in wasm_interface, "Wasm inspect adapter exposes HostProcess")

    for registry in ("settings.toml", "attributes.toml"):
        manifest = load(repo / "compat" / registry)
        expect(manifest["status"] == "implemented", f"{registry} is not implemented")
    builtins = load(repo / "compat/builtins.toml")
    expect(builtins["registry"]["status"] == "implemented", "builtins.toml is not implemented")

    counts = load(repo / "compat/test-counts.toml")["total"]
    expect(selected_tests("native") == counts["native"], "Native test outline count changed")
    expect(selected_tests("wasm") == counts["wasm1"], "wasm1 test outline count changed")


def main() -> int:
    argparse.ArgumentParser().parse_args()
    try:
        validate()
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"manifest verification error: {error}", file=sys.stderr)
        return 1
    print("structured compatibility manifests verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
