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
from collections import Counter
from pathlib import Path


EXPECTED_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
EXPECTED_REGISTRATIONS = 2417
EXPECTED_LEXER_REGISTRATIONS = 93
EXPECTED_TEST_LIST_SHA256 = "34773c9c59398fe3ac490aa7239b3c33a7b615159ff59b1e85ddef5e802381d9"
MAP_SCHEMA_VERSION = 4
HARNESS_SCHEMA_VERSION = 4
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
WINDOWS_ONLY_HARNESS_NAMES = {
    "windows::bare_bash_in_shebang",
    "windows::cmd_shell_expands_environment_variables",
    "windows::cmd_shell_receives_command_verbatim",
    "windows::cmd_shell_redirection",
    "windows_shell::windows_powershell_setting_uses_powershell",
    "windows_shell::windows_powershell_setting_uses_powershell_set_shell",
    "windows_shell::windows_shell_setting",
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


def incomplete_release_message(rows: list[dict[str, object]]) -> str:
    by_area = Counter(str(row.get("owner_area", "unknown")) for row in rows)
    breakdown = ", ".join(
        f"{area}={count}" for area, count in sorted(by_area.items())
    )
    sample = ", ".join(str(row.get("id", "unknown")) for row in rows[:12])
    suffix = ", ..." if len(rows) > 12 else ""
    return (
        f"strict release evidence is incomplete for {len(rows)} registrations "
        f"({breakdown}); first IDs: {sample}{suffix}"
    )


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


def validate_upstream_source(row_id: str, source: object) -> None:
    expect(isinstance(source, dict), f"{row_id} has no upstream source provenance")
    expect(
        set(source) == {"path", "line", "file_sha256"},
        f"{row_id} has an invalid upstream source schema",
    )
    expect(
        isinstance(source["path"], str)
        and source["path"]
        and not Path(source["path"]).is_absolute()
        and ".." not in Path(source["path"]).parts,
        f"{row_id} has an invalid upstream source path",
    )
    expect(
        isinstance(source["line"], int) and source["line"] > 0,
        f"{row_id} has an invalid upstream source line",
    )
    expect(
        isinstance(source["file_sha256"], str)
        and re.fullmatch(r"[0-9a-f]{64}", source["file_sha256"]) is not None,
        f"{row_id} has an invalid upstream source digest",
    )
def validate_harness_rows(
    harness_rows: list[dict[str, object]],
    expected_host: str,
    known_names: set[str],
) -> None:
    harness_by_name = {}
    for harness_row in harness_rows:
        name = harness_row["upstream_name"]
        expect(name in known_names, f"unknown official harness result {name}")
        expect(name not in harness_by_name, f"duplicate official harness result {name}")
        harness_by_name[name] = harness_row
        expect(harness_row.get("host") == expected_host, f"harness host changed for {name}")
        expect(
            harness_row["schema_version"] == HARNESS_SCHEMA_VERSION,
            f"tracked harness schema changed for {name}",
        )
        expect(harness_row["upstream_commit"] == EXPECTED_COMMIT, f"harness commit changed for {name}")
        expected_official = (
            "ignored"
            if harness_row["disposition"] == "upstream-ignored"
            else "passed"
        )
        expect(
            harness_row["official"] == expected_official,
            f"official harness status is inconsistent for {name}",
        )
        expect(
            harness_row["disposition"]
            in {
                "exact",
                "diagnostic-exact",
                "diagnostic-semantic",
                "product-identity",
                "excluded-completion",
                "upstream-ignored",
                "not-applicable",
            },
            f"harness result is not approved for {name}",
        )
        target_statuses = {harness_row["native"], harness_row["wasm1"]}
        disposition = harness_row["disposition"]
        if disposition == "exact":
            expect(target_statuses == {"exact"}, f"exact result drifted for {name}")
        elif disposition == "diagnostic-exact":
            expect(
                target_statuses <= {"exact", "diagnostic-exact"}
                and "diagnostic-exact" in target_statuses,
                f"diagnostic-exact result drifted for {name}",
            )
        elif disposition == "diagnostic-semantic":
            expect(
                target_statuses <= {
                    "exact",
                    "diagnostic-exact",
                    "diagnostic-semantic",
                }
                and "diagnostic-semantic" in target_statuses,
                f"diagnostic-semantic result drifted for {name}",
            )
        else:
            expect(
                target_statuses == {disposition},
                f"exception result drifted for {name}",
            )
        expect(
            harness_row["compatibility_rate_denominator"]
            == (
                harness_row["disposition"]
                not in {
                    "product-identity",
                    "excluded-completion",
                    "upstream-ignored",
                    "not-applicable",
                }
            ),
            f"harness denominator is inconsistent for {name}",
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
    for expected_host, filename, expected_count in (
        ("darwin-arm64", "harness-results.jsonl", 1842),
        ("windows-amd64", "harness-results-windows.jsonl", 1821),
    ):
        harness_rows = [
            json.loads(line)
            for line in (
                repo / "tests/upstream/just-1.57.0" / filename
            ).read_text(encoding="utf-8").splitlines()
        ]
        expect(
            len(harness_rows) == expected_count,
            f"{expected_host} official integration harness result count changed",
        )
        known_names = set(names)
        if expected_host == "windows-amd64":
            known_names |= WINDOWS_ONLY_HARNESS_NAMES
        validate_harness_rows(harness_rows, expected_host, known_names)
    harness_rows = [
        json.loads(line)
        for line in (
            repo / "tests/upstream/just-1.57.0/harness-results.jsonl"
        ).read_text(encoding="utf-8").splitlines()
    ]
    harness_by_name = {row["upstream_name"]: row for row in harness_rows}
    expect(len(harness_by_name) == len(harness_rows), "duplicate official harness result")
    expect(len(rows) == len(names), "upstream mapping row count does not match registrations")
    source_cache: dict[str, str] = {}
    contract_anchors: set[tuple[str, str]] = set()
    for index, (row, name) in enumerate(zip(rows, names), start=1):
        expect(row["schema_version"] == MAP_SCHEMA_VERSION, f"mapping schema changed at row {index}")
        expect(row["id"] == f"JUST-1.57.0-{index:04d}", f"invalid mapping id at row {index}")
        expect(row["upstream_name"] == name, f"mapping mismatch at row {index}")
        expect(row["owner_area"] in OWNER_AREAS, f"missing owner area at row {index}")
        expect(
            row["scope"]
            in {
                "compatibility",
                "excluded-completion",
                "product-identity",
                "upstream-internal",
            },
            f"invalid compatibility scope at row {index}",
        )
        expect(row["tracking"], f"missing tracking owner at row {index}")
        for evidence in row["evidence"]:
            expect((repo / evidence).exists(), f"missing evidence {evidence} at row {index}")
        if row["disposition"] == "verified-contract":
            validate_test_anchor(repo, row["id"], row.get("test_anchor"), source_cache)
            validate_upstream_source(row["id"], row.get("upstream_source"))
            expect(row["test_anchor"]["suite"] == row["evidence"][1], f"{row['id']} anchor suite differs from evidence")
            anchor_key = (
                row["test_anchor"]["suite"],
                row["test_anchor"]["test_name"],
            )
            expect(
                anchor_key not in contract_anchors,
                f"{row['id']} reuses contract anchor {anchor_key[0]}::{anchor_key[1]}",
            )
            contract_anchors.add(anchor_key)
        if row["disposition"] == "verified-differential":
            evidence_case = row.get("evidence_case")
            if isinstance(evidence_case, str) and evidence_case.startswith("MJ-UPSTREAM-HARNESS::"):
                harness = harness_by_name.get(name)
                expect(harness is not None, f"{row['id']} has no official harness result")
                expect(
                    harness["official"] == "passed"
                    and harness["native"] in {"exact", "diagnostic-exact"}
                    and harness["wasm1"] in {"exact", "diagnostic-exact"},
                    f"{row['id']} official harness result is not byte-exact",
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
                row["targets"]
                in (["native"], ["wasm1"], ["native", "wasm1"]),
                f"{row['owner_area']} row {index} has an invalid target matrix",
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
            expect(case.get("upstream_source") == expected.get("upstream_source"), f"{area} case source differs from test map")


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
    cli_source = (repo / "internal/cli/arguments.mbt").read_text(encoding="utf-8")
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
        expect(selected_tests(target, "internal/lexer") == expected_lexer_tests, f"{target} lexer test outline count changed")

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
        expect(
            manifest["status"] in {"implemented", "strict-remediation"},
            f"{area} has an invalid compatibility status",
        )
        if area == "query-cli":
            expect(
                manifest["plan_exit"]
                in {
                    "pending-remote-ci-and-audit",
                    "passed",
                    "blocked-by-strict-evidence",
                },
                "query CLI exit has an invalid state",
            )
            expect(manifest["evidence"]["native_tests"] == 134, "query CLI Native evidence count changed")
            expect(manifest["evidence"]["wasm_tests"] == 133, "query CLI wasm evidence count changed")
        elif area == "execution-context":
            expect(
                manifest["plan_exit"]
                in {
                    "pending-remote-ci",
                    "passed",
                    "blocked-by-strict-evidence",
                },
                "execution context exit has an invalid state",
            )
            expect(manifest["evidence"]["native_tests"] == 211, "execution context Native evidence count changed")
            expect(manifest["evidence"]["wasm_tests"] == 208, "execution context wasm evidence count changed")
        else:
            expect(
                manifest["plan_exit"]
                in {"passed", "blocked-by-strict-evidence"},
                f"{area} has an invalid compatibility exit",
            )
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
    expect(
        runtime_cache["status"] in {"implemented", "strict-remediation"},
        "runtime cache has an invalid compatibility status",
    )
    expect(
        runtime_cache["plan_exit"]
        in {"pending-remote-ci", "passed", "blocked-by-strict-evidence"},
        "runtime cache exit has an invalid state",
    )
    runtime_rows = [row for row in mapped_rows if row["owner_area"] == "runtime-cache"]
    expect(len(runtime_rows) == 74, "runtime cache registration count changed")
    expect(any(is_verified(row) for row in runtime_rows), "runtime cache has no executable evidence")
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
    expect(
        platform_compatibility["status"]
        in {"implemented", "strict-remediation"},
        "platform compatibility has an invalid status",
    )
    expect(
        platform_compatibility["plan_exit"] in {
            "pending-remote-ci-and-second-audit",
            "pending-remediation-ci-and-merge",
            "passed",
            "blocked-by-strict-evidence",
        },
        "platform compatibility exit has an invalid state",
    )
    platform_rows = [row for row in mapped_rows if row["owner_area"] == "platform-compatibility"]
    executor_rows = [row for row in mapped_rows if row["owner_area"] == "executor"]
    expect(len(platform_rows) == 52, "platform compatibility registration count changed")
    compatibility = platform_compatibility["compatibility"]
    expect(
        compatibility["covered_registrations"]
        == sum(is_verified(row) for row in platform_rows),
        "platform compatibility covered registration count changed",
    )
    expect(
        compatibility["unverified_registrations"]
        == sum(row["disposition"] == "unverified" for row in platform_rows),
        "platform compatibility unverified registration count changed",
    )
    expect(
        compatibility["unsupported_registrations"]
        == sum(row["disposition"] == "unsupported" for row in platform_rows),
        "platform compatibility unsupported registration count changed",
    )
    expect(
        compatibility["excluded_registrations"]
        == sum(
            row["disposition"] in {"excluded-completion", "not-applicable"}
            for row in platform_rows
        ),
        "platform compatibility excluded registration count changed",
    )
    expect(
        compatibility["executor_covered_registrations"]
        == sum(is_verified(row) for row in executor_rows),
        "executor covered registration count changed",
    )
    expect(
        compatibility["executor_unverified_registrations"]
        == sum(row["disposition"] == "unverified" for row in executor_rows),
        "executor unverified registration count changed",
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
    wasm_interface = (repo / "internal/host_wasm/pkg.generated.mbti").read_text(encoding="utf-8")
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


def validate_release(contract_results: Path) -> None:
    repo = root()
    rows = [
        json.loads(line)
        for line in (repo / "tests/upstream/just-1.57.0/test-map.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
    ]
    compatibility_rows = [
        row for row in rows if row["scope"] == "compatibility"
    ]
    incomplete = [
        row
        for row in compatibility_rows
        if row["disposition"] not in VERIFIED_DISPOSITIONS
    ]
    expect(
        all(
            row["targets"] == ["native", "wasm1"]
            for row in compatibility_rows
            if is_verified(row)
        ),
        "strict release target matrix is incomplete",
    )
    contract_rows = [row for row in rows if row["disposition"] == "verified-contract"]
    expect(contract_results.is_file(), f"contract execution results are missing: {contract_results}")
    executions = [
        json.loads(line)
        for line in contract_results.read_text(encoding="utf-8").splitlines()
    ]
    expected_executions = {
        (row["id"], target)
        for row in contract_rows
        for target in row["targets"]
    }
    actual_executions = {(row.get("case_id"), row.get("target")) for row in executions}
    expect(actual_executions == expected_executions, "contract execution target matrix differs")
    contract_by_id = {row["id"]: row for row in contract_rows}
    for execution in executions:
        row = contract_by_id[execution["case_id"]]
        expect(execution.get("schema_version") == 1, f"contract result schema changed for {row['id']}")
        expect(execution.get("passed") is True, f"contract execution failed for {row['id']}")
        expect(execution.get("upstream_commit") == EXPECTED_COMMIT, f"contract source commit changed for {row['id']}")
        expect(execution.get("upstream_name") == row["upstream_name"], f"contract upstream name changed for {row['id']}")
        expect(execution.get("upstream_source") == row["upstream_source"], f"contract source provenance changed for {row['id']}")
    expect(
        not incomplete,
        incomplete_release_message(incomplete),
    )
    completion_rows = [
        row for row in rows if row["scope"] == "excluded-completion"
    ]
    expect(
        completion_rows
        and all(
            row["disposition"] == "excluded-completion"
            for row in completion_rows
        ),
        "completion is not the sole explicit feature exclusion",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true")
    parser.add_argument(
        "--contract-results",
        type=Path,
        default=root() / "_build/upstream-contracts/results.jsonl",
    )
    args = parser.parse_args()
    try:
        validate()
        if args.release:
            validate_release(args.contract_results.resolve())
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"manifest verification error: {error}", file=sys.stderr)
        return 1
    print("structured compatibility manifests verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
