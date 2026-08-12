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
PHASE_9_STORAGE_DIFFERENCES = {
    "cache::clean_path_removes_empty_entries",
    "cache::clean_removes_cache_directory",
}
CLI_OPTION_NAMES = {
    "--alias-style", "--allow-missing", "--ceiling", "--check", "--chooser",
    "--clear-shell-args", "--color", "--command-color", "--complete-aliases",
    "--cygpath", "--default-list", "--dotenv-command", "--dotenv-filename",
    "--dotenv-path", "--dry-run", "--dump-format", "--evaluate-format", "--explain",
    "--global-justfile", "--group", "--highlight", "--indentation", "--jobs",
    "--justfile", "--justfile-name", "--list-heading", "--list-prefix", "--list-submodules",
    "--no-aliases", "--no-cache", "--no-deps", "--no-dotenv", "--no-highlight", "--one",
    "--quiet", "--set", "--shell", "--shell-arg", "--shell-command", "--tempdir", "--time",
    "--timestamp", "--timestamp-format", "--unsorted", "--unstable", "--verbose",
    "--working-directory", "--yes", "--help", "--version",
}
CLI_COMMAND_NAMES = {
    "--changelog", "--choose", "--clean", "--command", "--completions", "--dump", "--edit",
    "--evaluate", "--fmt", "--groups", "--init", "--json", "--list", "--man", "--request",
    "--show", "--summary", "--usage", "--variables",
}
SETTING_NAMES = {
    "allow-duplicate-recipes", "allow-duplicate-variables", "default-list", "default-script",
    "dotenv-command", "dotenv-filename", "dotenv-load", "dotenv-override", "dotenv-path",
    "dotenv-required", "export", "fallback", "guards", "ignore-comments", "indentation", "lazy",
    "lists", "minimum-version", "no-cd", "no-exit-message", "positional-arguments", "quiet",
    "script-interpreter", "shell", "tempdir", "unstable", "windows-powershell", "windows-shell",
    "working-directory",
}
ATTRIBUTE_NAMES = {
    "android", "arg", "cache", "confirm", "continue", "default", "doc", "dragonfly", "env",
    "exit-message", "extension", "freebsd", "group", "linux", "macos", "metadata", "netbsd",
    "no-cd", "no-exit-message", "no-quiet", "openbsd", "parallel", "positional-arguments", "private",
    "script", "shell", "unix", "windows", "working-directory",
}


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
        rf'^\s*(?:async\s+)?test\s+"{re.escape(test_name)}"\s*\{{',
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
        if row["owner_phase"] in {3, 4, 5, 6, 7, 8, 9, 10} and row["disposition"] == "covered-by":
            validate_test_anchor(repo, row["id"], row.get("test_anchor"), source_cache)
            expect(row["test_anchor"]["suite"] == row["evidence"][1], f"{row['id']} anchor suite differs from evidence")
        if row["owner_phase"] in {3, 4, 5, 6, 7, 8, 9, 10} and row["disposition"] == "covered-by":
            expect(row["disposition"] == "covered-by", f"Phase {row['owner_phase']} row {index} is not executable")
            expect(row["targets"] == ["native", "wasm1"], f"Phase {row['owner_phase']} row {index} target matrix is incomplete")
        expect(
            row["disposition"] != "planned",
            f"upstream registration {row['id']} remains planned",
        )

    lexer_names = [name for name in names if name.startswith("lexer::tests::")]
    expect(len(lexer_names) == EXPECTED_LEXER_REGISTRATIONS, "lexer registration count changed")
    phase2_rows = [row for row in rows if row["owner_phase"] == 2]
    expect(len(phase2_rows) == EXPECTED_LEXER_REGISTRATIONS, "Phase 2 mapping count changed")
    expect(
        all(row["disposition"] in {"covered-by", "not-applicable"} for row in phase2_rows),
        "Phase 2 contains an unclassified upstream registration",
    )
    for phase in (3, 4, 5, 6, 7, 8, 9, 10):
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
        expect(case["owner_phase"] >= 6, f"case {case_id} is assigned before Phase 6")
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
    expect(set(entry["name"] for entry in cli["option"]) == CLI_OPTION_NAMES, "CLI option inventory names changed")
    expect(set(entry["name"] for entry in cli["command"]) == CLI_COMMAND_NAMES, "CLI command inventory names changed")
    expect(
        all(entry["status"] in {"implemented", "unsupported", "excluded"} for entry in cli_entries),
        "CLI inventory contains an unclassified or invalid status",
    )
    for entry in cli_entries:
        if entry["status"] in {"unsupported", "excluded"}:
            expect(bool(entry.get("reason")), f"{entry['name']} lacks a status reason")
    expect(sum(entry["status"] == "implemented" for entry in cli["option"]) == 35, "implemented CLI option count changed")
    expect(sum(entry["status"] == "unsupported" for entry in cli["option"]) == 14, "unsupported CLI option count changed")
    expect(sum(entry["status"] == "excluded" for entry in cli["option"]) == 1, "excluded CLI option count changed")
    expect(sum(entry["status"] == "implemented" for entry in cli["command"]) == 14, "implemented CLI command count changed")
    expect(sum(entry["status"] == "unsupported" for entry in cli["command"]) == 1, "unsupported CLI command count changed")
    expect(sum(entry["status"] == "excluded" for entry in cli["command"]) == 4, "excluded CLI command count changed")

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

    for phase in (3, 4, 5, 6, 7):
        manifest = load(repo / f"compat/phase-{phase}.toml")
        expect(manifest["status"] == "implemented", f"Phase {phase} status is not implemented")
        if phase == 6:
            expect(
                manifest["plan_exit"] in {"pending-remote-ci-and-audit", "passed"},
                "Phase 6 exit has an invalid state",
            )
            expect(manifest["evidence"]["native_tests"] == 134, "Phase 6 Native evidence count changed")
            expect(manifest["evidence"]["wasm_tests"] == 133, "Phase 6 wasm evidence count changed")
        elif phase == 7:
            expect(
                manifest["plan_exit"] in {"pending-remote-ci", "passed"},
                "Phase 7 exit has an invalid state",
            )
            expect(manifest["evidence"]["native_tests"] == 211, "Phase 7 Native evidence count changed")
            expect(manifest["evidence"]["wasm_tests"] == 208, "Phase 7 wasm evidence count changed")
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
        if phase == 7:
            phase7_rows = [
                json.loads(line)
                for line in (
                    repo / "tests/upstream/just-1.57.0/test-map.jsonl"
                ).read_text(encoding="utf-8").splitlines()
                if json.loads(line)["owner_phase"] == 7
            ]
            expect(
                corpus["covered_registrations"] == sum(
                    row["disposition"] == "covered-by" for row in phase7_rows
                ),
                "Phase 7 covered registration count changed",
            )
            expect(
                all(row["disposition"] == "covered-by" for row in phase7_rows),
                "Phase 7 contains a registration without executable evidence",
            )
            expect(
                corpus["dotenv"]["registrations"] == 51,
                "Phase 7 dotenv registration count changed",
            )
            expect(
                corpus["invocation"]["registrations"] == 86,
                "Phase 7 invocation registration count changed",
            )
            expect(
                corpus["working_directory"]["registrations"] == 30,
                "Phase 7 working-directory registration count changed",
            )
            expect(
                corpus["environment"]["registrations"] == 21,
                "Phase 7 environment registration count changed",
            )
            expect(
                manifest["evidence"]["upstream_covered_registrations"]
                == corpus["covered_registrations"],
                "Phase 7 compatibility and corpus counts differ",
            )

    phase9 = load(repo / "compat/phase-9.toml")
    expect(phase9["status"] == "implemented", "Phase 9 status is not implemented")
    expect(
        phase9["plan_exit"] in {"pending-remote-ci", "passed"},
        "Phase 9 exit has an invalid state",
    )
    phase9_rows = [
        json.loads(line)
        for line in (repo / "tests/upstream/just-1.57.0/test-map.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
        if json.loads(line)["owner_phase"] == 9
    ]
    expect(len(phase9_rows) == 74, "Phase 9 registration count changed")
    expect(
        sum(row["disposition"] == "covered-by" for row in phase9_rows) == 72,
        "Phase 9 executable registration count changed",
    )
    phase9_differences = [
        row for row in phase9_rows if row["disposition"] == "unsupported"
    ]
    expect(
        {row["upstream_name"] for row in phase9_differences}
        == PHASE_9_STORAGE_DIFFERENCES,
        "Phase 9 storage differences changed",
    )
    expect(
        all(
            row["targets"] == ["native", "wasm1"]
            and row["tracking"] == "PROJECT_PLAN_PR-105"
            and row.get("reason")
            for row in phase9_differences
        ),
        "Phase 9 storage differences lack targets, tracking, or reasons",
    )

    phase10 = load(repo / "compat/phase-10.toml")
    expect(phase10["status"] == "implemented", "Phase 10 status is not implemented")
    expect(
        phase10["plan_exit"] in {"pending-remote-ci-and-second-audit", "passed"},
        "Phase 10 exit has an invalid state",
    )
    phase10_rows = [
        json.loads(line)
        for line in (repo / "tests/upstream/just-1.57.0/test-map.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
        if json.loads(line)["owner_phase"] == 10
    ]
    phase8_rows = [
        json.loads(line)
        for line in (repo / "tests/upstream/just-1.57.0/test-map.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
        if json.loads(line)["owner_phase"] == 8
    ]
    expect(len(phase10_rows) == 52, "Phase 10 registration count changed")
    compatibility = phase10["compatibility"]
    expect(
        compatibility["covered_registrations"]
        == sum(row["disposition"] == "covered-by" for row in phase10_rows)
        == 40,
        "Phase 10 covered registration count changed",
    )
    expect(
        compatibility["unsupported_registrations"]
        == sum(row["disposition"] == "unsupported" for row in phase10_rows)
        == 4,
        "Phase 10 unsupported registration count changed",
    )
    expect(
        compatibility["excluded_registrations"]
        == sum(row["disposition"] in {"excluded-completion", "not-applicable"} for row in phase10_rows)
        == 8,
        "Phase 10 excluded registration count changed",
    )
    expect(
        compatibility["phase_8_covered_registrations"]
        == sum(row["disposition"] == "covered-by" for row in phase8_rows)
        == 209,
        "Phase 8 covered registration count changed",
    )
    expect(
        compatibility["phase_8_unsupported_registrations"]
        == sum(row["disposition"] == "unsupported" for row in phase8_rows)
        == 520,
        "Phase 8 unsupported registration count changed",
    )
    expect(
        compatibility["phase_8_not_applicable_registrations"]
        == sum(row["disposition"] == "not-applicable" for row in phase8_rows)
        == 3,
        "Phase 8 not-applicable registration count changed",
    )
    expect(compatibility["planned_registrations"] == 0, "Phase 10 records planned registrations")
    for evidence in phase10["evidence"].values():
        expect((repo / evidence).exists(), f"Phase 10 evidence is missing: {evidence}")

    policy = load(repo / "policies/inspect.toml")
    expect(policy["fs"]["write"] == [], "Phase 6 inspect policy grants filesystem writes")
    expect(policy["process"]["spawn"] is False, "Phase 6 inspect policy grants process spawn")
    expect(policy["net"] == {"dns": [], "connect": [], "bind": []}, "Phase 6 inspect policy grants network access")
    wasm_interface = (repo / "src/host_wasm/pkg.generated.mbti").read_text(encoding="utf-8")
    expect("HostProcess" not in wasm_interface, "Wasm inspect adapter exposes HostProcess")

    settings = load(repo / "compat/settings.toml")
    expect(set(entry["name"] for entry in settings["setting"]) == SETTING_NAMES, "settings inventory names changed")
    for entry in settings["setting"]:
        expect(entry["status"] in {"implemented", "unsupported"}, f"setting {entry['name']} is unclassified")
        if entry["status"] == "unsupported":
            expect(bool(entry.get("reason")), f"setting {entry['name']} lacks a reason")
    expect(sum(entry["status"] == "implemented" for entry in settings["setting"]) == 17, "implemented setting count changed")
    expect(sum(entry["status"] == "unsupported" for entry in settings["setting"]) == 12, "unsupported setting count changed")
    attributes = load(repo / "compat/attributes.toml")
    expect(set(entry["name"] for entry in attributes["attribute"]) == ATTRIBUTE_NAMES, "attributes inventory names changed")
    for entry in attributes["attribute"]:
        expect(entry["status"] in {"implemented", "unsupported"}, f"attribute {entry['name']} is unclassified")
        if entry["status"] == "unsupported":
            expect(bool(entry.get("reason")), f"attribute {entry['name']} lacks a reason")
    expect(sum(entry["status"] == "implemented" for entry in attributes["attribute"]) == 22, "implemented attribute count changed")
    expect(sum(entry["status"] == "unsupported" for entry in attributes["attribute"]) == 7, "unsupported attribute count changed")
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
