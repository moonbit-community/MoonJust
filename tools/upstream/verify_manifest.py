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
MAP_SCHEMA_VERSION = 3
VERIFIED_DISPOSITIONS = {"verified-differential", "verified-contract"}
OWNER_AREAS = {
    "lexer",
    "parser-formatter",
    "semantic-loader",
    "evaluator-builtins",
    "query-cli",
    "execution-context",
    "executor",
    "runtime-cache",
    "platform-compatibility",
}
AREA_CASE_MANIFESTS = {
    "parser-formatter": "parser-formatter-cases.jsonl",
    "semantic-loader": "semantic-loader-cases.jsonl",
    "evaluator-builtins": "evaluator-builtins-cases.jsonl",
    "query-cli": "query-cli-cases.jsonl",
    "execution-context": "execution-context-cases.jsonl",
    "executor": "executor-cases.jsonl",
    "runtime-cache": "runtime-cache-cases.jsonl",
    "platform-compatibility": "platform-compatibility-cases.jsonl",
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
CLI_ENV_BINDINGS = {
    "JUST_ALIAS_STYLE": "--alias-style",
    "JUST_ALLOW_MISSING": "--allow-missing",
    "JUST_CEILING": "--ceiling",
    "JUST_CHOOSER": "--chooser",
    "JUST_COLOR": "--color",
    "JUST_COMMAND_COLOR": "--command-color",
    "JUST_COMPLETE_ALIASES": "--complete-aliases",
    "JUST_CYGPATH": "--cygpath",
    "JUST_DEFAULT_LIST": "--default-list",
    "JUST_DOTENV_COMMAND": "--dotenv-command",
    "JUST_DRY_RUN": "--dry-run",
    "JUST_DUMP_FORMAT": "--dump-format",
    "JUST_EVALUATE_FORMAT": "--evaluate-format",
    "JUST_EXPLAIN": "--explain",
    "JUST_GROUP": "--group",
    "JUST_HIGHLIGHT": "--highlight",
    "JUST_INDENTATION": "--indentation",
    "JUST_JOBS": "--jobs",
    "JUST_JUSTFILE": "--justfile",
    "JUST_JUSTFILE_NAME": "--justfile-name",
    "JUST_LIST_HEADING": "--list-heading",
    "JUST_LIST_PREFIX": "--list-prefix",
    "JUST_LIST_SUBMODULES": "--list-submodules",
    "JUST_NO_ALIASES": "--no-aliases",
    "JUST_NO_CACHE": "--no-cache",
    "JUST_NO_DEPS": "--no-deps",
    "JUST_NO_DOTENV": "--no-dotenv",
    "JUST_NO_HIGHLIGHT": "--no-highlight",
    "JUST_ONE": "--one",
    "JUST_QUIET": "--quiet",
    "JUST_TEMPDIR": "--tempdir",
    "JUST_TIME": "--time",
    "JUST_TIMESTAMP": "--timestamp",
    "JUST_TIMESTAMP_FORMAT": "--timestamp-format",
    "JUST_UNSORTED": "--unsorted",
    "JUST_UNSTABLE": "--unstable",
    "JUST_VERBOSE": "--verbose",
    "JUST_WORKING_DIRECTORY": "--working-directory",
    "JUST_YES": "--yes",
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


def is_verified(row: dict) -> bool:
    return row.get("disposition") in VERIFIED_DISPOSITIONS


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
    differential = load(repo / "tests/differential/cases.toml")
    differential_cases = {case["id"]: case for case in differential["case"]}
    harness_rows = [
        json.loads(line)
        for line in (
            repo / "tests/upstream/just-1.57.0/harness-results.jsonl"
        ).read_text(encoding="utf-8").splitlines()
    ]
    expect(len(harness_rows) == 1842, "official integration harness result count changed")
    harness_by_name = {}
    for harness_row in harness_rows:
        name = harness_row["upstream_name"]
        expect(name not in harness_by_name, f"duplicate official harness result {name}")
        harness_by_name[name] = harness_row
        expect(harness_row["schema_version"] == MAP_SCHEMA_VERSION, f"harness schema changed for {name}")
        expect(harness_row["upstream_commit"] == EXPECTED_COMMIT, f"harness commit changed for {name}")
        expect(
            harness_row["disposition"]
            == (
                "verified-differential"
                if harness_row["official"] == "passed"
                and harness_row["native"] in {"passed", "diagnostic-style", "product-identity"}
                and harness_row["wasm1"] in {"passed", "diagnostic-style", "product-identity"}
                else "unverified"
            ),
            f"harness disposition is inconsistent for {name}",
        )
        expect(
            harness_row.get("allowed_difference")
            == (
                "product-identity"
                if "product-identity"
                in {harness_row["native"], harness_row["wasm1"]}
                else (
                    "diagnostic-style"
                    if "diagnostic-style"
                    in {harness_row["native"], harness_row["wasm1"]}
                    else "none"
                )
            ),
            f"harness difference classification is inconsistent for {name}",
        )
    expect(len(rows) == len(names), "upstream mapping row count does not match registrations")
    source_cache: dict[str, str] = {}
    for index, (row, name) in enumerate(zip(rows, names), start=1):
        expect(row["schema_version"] == MAP_SCHEMA_VERSION, f"mapping schema changed at row {index}")
        expect(row["id"] == f"JUST-1.57.0-{index:04d}", f"invalid mapping id at row {index}")
        expect(row["upstream_name"] == name, f"mapping mismatch at row {index}")
        expect(row["owner_area"] in OWNER_AREAS, f"missing owner area at row {index}")
        expect(row["tier"] in {"A", "B", "W", "X"}, f"invalid tier at row {index}")
        expect(row["tracking"], f"missing tracking owner at row {index}")
        for evidence in row["evidence"]:
            expect((repo / evidence).exists(), f"missing evidence {evidence} at row {index}")
        if row["disposition"] == "verified-contract":
            validate_test_anchor(repo, row["id"], row.get("test_anchor"), source_cache)
            expect(row["test_anchor"]["suite"] == row["evidence"][1], f"{row['id']} anchor suite differs from evidence")
        if row["disposition"] == "verified-differential":
            evidence_case = row.get("evidence_case")
            if isinstance(evidence_case, str) and evidence_case.startswith("MJ-UPSTREAM-HARNESS::"):
                harness = harness_by_name.get(name)
                expect(harness is not None, f"{row['id']} has no official harness result")
                expect(
                    harness["disposition"] == "verified-differential",
                    f"{row['id']} official harness result is not verified",
                )
                expect(
                    evidence_case == f"MJ-UPSTREAM-HARNESS::{name}",
                    f"{row['id']} official harness case differs",
                )
            else:
                expect(evidence_case in differential_cases, f"{row['id']} has no differential case")
                expect(
                    name in differential_cases[evidence_case].get("upstream_tests", []),
                    f"{row['id']} is not declared by differential case {evidence_case}",
                )
        if is_verified(row):
            expect(
                row["targets"] == ["native", "wasm1"],
                f"{row['owner_area']} row {index} target matrix is incomplete",
            )
        expect(
            row["disposition"] != "planned",
            f"upstream registration {row['id']} remains planned",
        )

    lexer_names = [name for name in names if name.startswith("lexer::tests::")]
    expect(len(lexer_names) == EXPECTED_LEXER_REGISTRATIONS, "lexer registration count changed")
    lexer_rows = [row for row in rows if row["owner_area"] == "lexer"]
    expect(len(lexer_rows) == EXPECTED_LEXER_REGISTRATIONS, "lexer mapping count changed")
    expect(
        all(row["disposition"] in VERIFIED_DISPOSITIONS | {"unverified", "not-applicable"} for row in lexer_rows),
        "lexer contains an unclassified upstream registration",
    )
    for area, filename in AREA_CASE_MANIFESTS.items():
        cases = repo / "tests/upstream/just-1.57.0" / filename
        rows_for_area = [
            row
            for row in rows
            if row["owner_area"] == area and is_verified(row)
        ]
        case_rows = [json.loads(line) for line in cases.read_text(encoding="utf-8").splitlines()]
        expect(len(case_rows) == len(rows_for_area), f"{area} case manifest count changed")
        expected_by_id = {row["id"]: row for row in rows_for_area}
        for case in case_rows:
            expect(case["disposition"] in VERIFIED_DISPOSITIONS, f"{area} has non-executable cases")
            expected = expected_by_id.get(case.get("case_id"))
            expect(expected is not None, f"{area} case has an unknown id")
            expect(case.get("test_anchor") == expected.get("test_anchor"), f"{area} case anchor differs from test map")


def validate_differential_cases() -> None:
    repo = root()
    manifest = load(repo / "tests/differential/cases.toml")
    expect(manifest["schema_version"] == 3, "differential manifest schema changed")
    cases = manifest.get("case", [])
    expect(len(cases) == 182, "differential case count changed")
    seen = set()
    upstream_names = set(
        (repo / "tests/upstream/just-1.57.0/test-list.txt")
        .read_text(encoding="utf-8")
        .splitlines()
    )
    for case in cases:
        case_id = case["id"]
        expect(case_id not in seen, f"duplicate differential case {case_id}")
        seen.add(case_id)
        status = case["status"]
        expect(status in {"match", "expected-difference"}, f"case {case_id} is not classified")
        expect(isinstance(case.get("upstream_tests", []), list), f"case {case_id} has invalid upstream_tests")
        for upstream_test in case.get("upstream_tests", []):
            expect(upstream_test in upstream_names, f"case {case_id} names unknown upstream test {upstream_test}")
        if status == "expected-difference":
            expect(case.get("allowed_difference", "none") != "none", f"case {case_id} has an unbounded difference")
        expect(
            case["owner_area"]
            in {"query-cli", "execution-context", "executor", "runtime-cache", "platform-compatibility"},
            f"case {case_id} has an invalid owner area",
        )
        case_dir = repo / "tests/differential/cases" / case["directory"]
        allowed_entries = {
            "argv.txt",
            "compat-id",
            "env.list",
            "expectation",
            "stdin",
            "tree",
        }
        unexpected_entries = sorted(
            entry.name for entry in case_dir.iterdir() if entry.name not in allowed_entries
        )
        expect(
            not unexpected_entries,
            f"case {case_id} has unknown entries: {', '.join(unexpected_entries)}",
        )
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
    oracle = repo / "tests/upstream/just-1.57.0/evaluator-oracle.jsonl"
    oracle_rows = [json.loads(line) for line in oracle.read_text(encoding="utf-8").splitlines()]
    expect(len(oracle_rows) == 20, "evaluator Rust oracle count changed")
    expect(len({row["id"] for row in oracle_rows}) == 20, "evaluator Rust oracle ids are not unique")
    expect(all(row["schema_version"] == 2 for row in oracle_rows), "evaluator Rust oracle schema changed")
    expect(sum(row["id"].startswith("MJ-EVAL-SEMVER-") for row in oracle_rows) == 16, "SemVer oracle count changed")
    expect(sum(row["id"].startswith("MJ-EVAL-REGEX-") for row in oracle_rows) == 4, "regexp oracle count changed")
    for row in oracle_rows:
        expect(row["builtin"] in {"semver_matches", "replace_regex"}, f"invalid evaluator oracle builtin {row['builtin']}")
        expect(isinstance(row["arguments"], list), f"evaluator oracle {row['id']} arguments are not structured")
        expect(("expected" in row) != ("expected_error" in row), f"evaluator oracle {row['id']} has an ambiguous outcome")


def validate() -> None:
    repo = root()
    upstream = load(repo / "compat/just-1.57.0.toml")
    expect(upstream["schema_version"] == 3, "compatibility index schema changed")
    expect(upstream["upstream"]["commit"] == EXPECTED_COMMIT, "upstream commit changed")
    expect(upstream["test_inventory"]["registrations"] == EXPECTED_REGISTRATIONS, "registration count changed")
    expect(upstream["test_inventory"]["mapping_schema"] == MAP_SCHEMA_VERSION, "mapping schema is not pinned")
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
    manifest_env_bindings = {
        entry["env"]: entry["name"]
        for entry in cli["option"]
        if "env" in entry
    }
    expect(
        manifest_env_bindings == CLI_ENV_BINDINGS,
        "CLI environment bindings differ from upstream arguments.rs",
    )
    for entry in cli["option"]:
        if "env" not in entry:
            continue
        env_status = entry.get("env_status", entry["status"])
        expect(
            env_status in {"implemented", "unsupported"},
            f"{entry['env']} has an invalid environment status",
        )
        if env_status == "unsupported" and entry["status"] == "implemented":
            expect(
                bool(entry.get("env_reason")),
                f"{entry['env']} lacks an environment-specific reason",
            )
    cli_source = (repo / "src/cli/arguments.mbt").read_text(encoding="utf-8")
    implemented_env = {
        entry["env"]
        for entry in cli["option"]
        if "env" in entry and entry.get("env_status", entry["status"]) == "implemented"
    }
    unsupported_env = set(CLI_ENV_BINDINGS) - implemented_env
    for name in implemented_env:
        expect(
            f'env="{name}"' in cli_source,
            f"implemented CLI environment binding {name} is not registered",
        )
    for name in unsupported_env:
        expect(
            f'("{name}",' in cli_source or f'env.get("{name}")' in cli_source,
            f"unsupported CLI environment binding {name} lacks an explicit diagnostic",
        )
    main_source = (repo / "cmd/just/main.mbt").read_text(encoding="utf-8")
    expect(
        "HostEnv::env_entries(environment_host)" in main_source,
        "production CLI does not pass the HostEnv snapshot to argparse",
    )
    platform_gate = (repo / "tools/checks/platform.sh").read_text(encoding="utf-8")
    for required_probe in ("JUST_YES=1", "JUST_JUSTFILE=-"):
        expect(
            required_probe in platform_gate,
            f"platform gate lacks {required_probe} entry-point coverage",
        )
    expect(sum(entry["status"] == "implemented" for entry in cli["option"]) == 48, "implemented CLI option count changed")
    expect(sum(entry["status"] == "unsupported" for entry in cli["option"]) == 1, "unsupported CLI option count changed")
    expect(sum(entry["status"] == "excluded" for entry in cli["option"]) == 1, "excluded CLI option count changed")
    expect(sum(entry["status"] == "implemented" for entry in cli["command"]) == 15, "implemented CLI command count changed")
    expect(sum(entry["status"] == "unsupported" for entry in cli["command"]) == 0, "unsupported CLI command count changed")
    expect(sum(entry["status"] == "excluded" for entry in cli["command"]) == 4, "excluded CLI command count changed")

    builtins = load(repo / "compat/builtins.toml")
    expect(builtins["registry"]["canonical_count"] == 83, "builtin count changed")
    expect(len(builtins["registry"]["canonical"]) == 83, "builtin inventory length changed")
    expect(len(set(builtins["registry"]["canonical"])) == 83, "builtin inventory contains duplicates")
    validate_builtins(builtins)

    core_contracts = load(repo / "compat/core-contracts.toml")
    expect(core_contracts["area"] == "core-contracts", "core contract area changed")
    contracts = core_contracts["contract"]
    expect(len(contracts) == 5, "core contract count changed")
    expect(
        all(c["status"] == "implemented" and c["native"] == "pass" and c["wasm1"] == "pass" for c in contracts),
        "core contract evidence is incomplete",
    )
    core_expected = {c["package"]: c["black_box_tests"] for c in contracts}
    for target in ("native", "wasm"):
        for package, expected in core_expected.items():
            expect(
                selected_tests(target, package) == expected,
                f"{target} {package} test outline count changed",
            )

    lexer = load(repo / "compat/lexer.toml")
    expect(lexer["area"] == "lexer", "lexer area changed")
    inventory = lexer["upstream_lexer_inventory"]
    expect(inventory["registrations"] == EXPECTED_LEXER_REGISTRATIONS, "lexer registration count changed")
    expect(len(lexer["contract"]) == 5, "lexer contract count changed")
    expect(
        all(c["status"] == "implemented" and c["native"] == "pass" and c["wasm1"] == "pass" for c in lexer["contract"]),
        "lexer contract evidence is incomplete",
    )
    expect(inventory["random_inputs"] == 100000, "lexer hardening budget changed")
    expect(inventory["adapted_success_cases"] == 16, "lexer success-oracle count changed")
    expect(inventory["adapted_error_cases"] == 5, "lexer error-oracle count changed")
    expected_lexer_tests = sum(c["black_box_tests"] for c in lexer["contract"])
    for target in ("native", "wasm"):
        expect(selected_tests(target, "src/lexer") == expected_lexer_tests, f"{target} lexer test outline count changed")

    area_sources = {
        "parser-formatter": ("compat/parser-formatter.toml", "parser-formatter.toml"),
        "semantic-loader": ("compat/semantic-loader.toml", "semantic-loader.toml"),
        "evaluator-builtins": ("compat/evaluator-builtins.toml", "evaluator-builtins.toml"),
        "query-cli": ("compat/query-cli.toml", "query-cli.toml"),
        "execution-context": ("compat/execution-context.toml", "execution-context.toml"),
    }
    mapped_rows = [
        json.loads(line)
        for line in (repo / "tests/upstream/just-1.57.0/test-map.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
    ]
    for area, (manifest_path, corpus_name) in area_sources.items():
        manifest = load(repo / manifest_path)
        expect(manifest["area"] == area, f"{area} manifest area changed")
        expect(manifest["status"] == "implemented", f"{area} status is not implemented")
        if area == "query-cli":
            expect(
                manifest["plan_exit"] in {"pending-remote-ci-and-audit", "passed"},
                "query CLI exit has an invalid state",
            )
            expect(manifest["evidence"]["native_tests"] == 134, "query CLI Native evidence count changed")
            expect(manifest["evidence"]["wasm_tests"] == 133, "query CLI wasm evidence count changed")
        elif area == "execution-context":
            expect(
                manifest["plan_exit"] in {"pending-remote-ci", "passed"},
                "execution context exit has an invalid state",
            )
            expect(manifest["evidence"]["native_tests"] == 211, "execution context Native evidence count changed")
            expect(manifest["evidence"]["wasm_tests"] == 208, "execution context wasm evidence count changed")
        else:
            expect(manifest["plan_exit"] == "passed", f"{area} exit is not passed")
        corpus = load(repo / "tests/upstream/just-1.57.0" / corpus_name)
        expect(corpus["area"] == area, f"{area} corpus area changed")
        expect(corpus["upstream_commit"] == EXPECTED_COMMIT, f"{area} corpus commit changed")
        expect(corpus["license"] == "CC0-1.0", f"{area} corpus license changed")
        if area == "query-cli":
            query_rows = [row for row in mapped_rows if row["owner_area"] == area]
            expect(
                corpus["covered_registrations"] == sum(
                    is_verified(row) for row in query_rows
                ),
                "query CLI covered registration count changed",
            )
            expect(
                corpus["excluded_registrations"] == sum(
                    row["disposition"] in {"excluded-completion", "not-applicable"}
                    for row in query_rows
                ),
                "query CLI excluded registration count changed",
            )
        if area == "execution-context":
            context_rows = [row for row in mapped_rows if row["owner_area"] == area]
            expect(
                corpus["covered_registrations"] == sum(
                    is_verified(row) for row in context_rows
                ),
                "execution context covered registration count changed",
            )
            expect(
                all(is_verified(row) or row["disposition"] == "unverified" for row in context_rows),
                "execution context contains a registration without executable evidence",
            )
            expect(corpus["dotenv"]["registrations"] == 51, "dotenv registration count changed")
            expect(corpus["invocation"]["registrations"] == 86, "invocation registration count changed")
            expect(corpus["working_directory"]["registrations"] == 30, "working-directory registration count changed")
            expect(corpus["environment"]["registrations"] == 21, "environment registration count changed")
            expect(
                manifest["evidence"]["upstream_covered_registrations"]
                == corpus["covered_registrations"],
                "execution context compatibility and corpus counts differ",
            )

    runtime_cache = load(repo / "compat/runtime-cache.toml")
    expect(runtime_cache["area"] == "runtime-cache", "runtime cache area changed")
    expect(runtime_cache["status"] == "implemented", "runtime cache status is not implemented")
    expect(
        runtime_cache["plan_exit"] in {"pending-remote-ci", "passed"},
        "runtime cache exit has an invalid state",
    )
    runtime_rows = [row for row in mapped_rows if row["owner_area"] == "runtime-cache"]
    expect(len(runtime_rows) == 74, "runtime cache registration count changed")
    expect(
        sum(is_verified(row) for row in runtime_rows) == 74,
        "runtime cache executable registration count changed",
    )
    runtime_differences = [row for row in runtime_rows if row["disposition"] == "unsupported"]
    expect(not runtime_differences, "runtime cache still contains unsupported registrations")
    expect(
        all(
            row["targets"] == ["native", "wasm1"]
            and row["tracking"] == "PROJECT_PLAN_PR-105"
            and row.get("reason")
            for row in runtime_differences
        ),
        "runtime cache storage differences lack targets, tracking, or reasons",
    )

    platform_compatibility = load(repo / "compat/platform-compatibility.toml")
    expect(platform_compatibility["area"] == "platform-compatibility", "platform compatibility area changed")
    expect(platform_compatibility["status"] == "implemented", "platform compatibility status is not implemented")
    expect(
        platform_compatibility["plan_exit"] in {
            "pending-remote-ci-and-second-audit",
            "pending-remediation-ci-and-merge",
            "passed",
        },
        "platform compatibility exit has an invalid state",
    )
    platform_rows = [row for row in mapped_rows if row["owner_area"] == "platform-compatibility"]
    executor_rows = [row for row in mapped_rows if row["owner_area"] == "executor"]
    expect(len(platform_rows) == 52, "platform compatibility registration count changed")
    compatibility = platform_compatibility["compatibility"]
    expect(
        compatibility["covered_registrations"]
        == sum(is_verified(row) for row in platform_rows)
        == 40,
        "platform compatibility covered registration count changed",
    )
    expect(
        compatibility["unsupported_registrations"]
        == sum(row["disposition"] == "unsupported" for row in platform_rows)
        == 4,
        "platform compatibility unsupported registration count changed",
    )
    expect(
        compatibility["excluded_registrations"]
        == sum(row["disposition"] in {"excluded-completion", "not-applicable"} for row in platform_rows)
        == 8,
        "platform compatibility excluded registration count changed",
    )
    expect(
        compatibility["executor_covered_registrations"]
        == sum(is_verified(row) for row in executor_rows),
        "executor covered registration count changed",
    )
    expect(
        compatibility["executor_unsupported_registrations"]
        == sum(row["disposition"] == "unsupported" for row in executor_rows),
        "executor unsupported registration count changed",
    )
    expect(
        compatibility["executor_not_applicable_registrations"]
        == sum(row["disposition"] == "not-applicable" for row in executor_rows),
        "executor not-applicable registration count changed",
    )
    expect(compatibility["planned_registrations"] == 0, "platform compatibility records planned registrations")
    for evidence in platform_compatibility["evidence"].values():
        expect((repo / evidence).exists(), f"platform compatibility evidence is missing: {evidence}")

    policy = load(repo / "policies/inspect.toml")
    expect(policy["fs"]["write"] == [], "inspect policy grants filesystem writes")
    expect(policy["process"]["spawn"] is False, "inspect policy grants process spawn")
    expect(policy["net"] == {"dns": [], "connect": [], "bind": []}, "inspect policy grants network access")
    wasm_interface = (repo / "src/host_wasm/pkg.generated.mbti").read_text(encoding="utf-8")
    expect("HostProcess" not in wasm_interface, "Wasm inspect adapter exposes HostProcess")

    settings = load(repo / "compat/settings.toml")
    expect(set(entry["name"] for entry in settings["setting"]) == SETTING_NAMES, "settings inventory names changed")
    for entry in settings["setting"]:
        expect(entry["status"] in {"implemented", "unsupported"}, f"setting {entry['name']} is unclassified")
        if entry["status"] == "unsupported":
            expect(bool(entry.get("reason")), f"setting {entry['name']} lacks a reason")
    expect(sum(entry["status"] == "implemented" for entry in settings["setting"]) == 28, "implemented setting count changed")
    expect(sum(entry["status"] == "unsupported" for entry in settings["setting"]) == 1, "unsupported setting count changed")
    attributes = load(repo / "compat/attributes.toml")
    expect(set(entry["name"] for entry in attributes["attribute"]) == ATTRIBUTE_NAMES, "attributes inventory names changed")
    for entry in attributes["attribute"]:
        expect(entry["status"] in {"implemented", "unsupported"}, f"attribute {entry['name']} is unclassified")
        if entry["status"] == "unsupported":
            expect(bool(entry.get("reason")), f"attribute {entry['name']} lacks a reason")
    expect(sum(entry["status"] == "implemented" for entry in attributes["attribute"]) == 29, "implemented attribute count changed")
    expect(sum(entry["status"] == "unsupported" for entry in attributes["attribute"]) == 0, "unsupported attribute count changed")
    builtins = load(repo / "compat/builtins.toml")
    expect(builtins["registry"]["status"] == "implemented", "builtins.toml is not implemented")

    counts = load(repo / "compat/test-counts.toml")["total"]
    expect(selected_tests("native") == counts["native"], "Native test outline count changed")
    expect(selected_tests("wasm") == counts["wasm1"], "wasm1 test outline count changed")


def validate_release() -> None:
    repo = root()
    rows = [
        json.loads(line)
        for line in (repo / "tests/upstream/just-1.57.0/test-map.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
    ]
    tier_a = [row for row in rows if row["tier"] == "A"]
    incomplete = [
        row
        for row in tier_a
        if row["disposition"] not in VERIFIED_DISPOSITIONS | {"not-applicable"}
    ]
    expect(not incomplete, f"Tier A release evidence is incomplete for {len(incomplete)} registrations")
    expect(
        all(row["targets"] == ["native", "wasm1"] for row in tier_a if is_verified(row)),
        "Tier A release target matrix is incomplete",
    )
    for manifest_name, key in (
        ("cli-options.toml", "option"),
        ("settings.toml", "setting"),
        ("attributes.toml", "attribute"),
    ):
        manifest = load(repo / "compat" / manifest_name)
        entries = list(manifest[key])
        if manifest_name == "cli-options.toml":
            entries.extend(manifest["command"])
        remaining = [entry for entry in entries if entry.get("tier") == "A" and entry["status"] != "implemented"]
        expect(not remaining, f"{manifest_name} has {len(remaining)} incomplete Tier A entries")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true")
    args = parser.parse_args()
    try:
        validate()
        if args.release:
            validate_release()
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"manifest verification error: {error}", file=sys.stderr)
        return 1
    print("structured compatibility manifests verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
