#!/usr/bin/env python3
"""Generate and validate the pinned upstream-test ownership map."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
EXPECTED_COUNT = 2417
EXPECTED_LIST_SHA256 = (
    "34773c9c59398fe3ac490aa7239b3c33a7b615159ff59b1e85ddef5e802381d9"
)

PHASE_PREFIXES = {
    2: {"lexer"},
    3: {"format", "markdown", "parser", "tangle"},
    4: {
        "alias",
        "allow_duplicate_recipes",
        "allow_duplicate_variables",
        "analyzer",
        "arg_attribute",
        "attribute",
        "attributes",
        "compiler",
        "ceiling",
        "dependencies",
        "fallback",
        "global",
        "imports",
        "minimum_version",
        "mapped_dependencies",
        "modules",
        "modulepath",
        "no_dependencies",
        "os_attributes",
        "parameters",
        "recipe_resolver",
        "search",
        "search_arguments",
        "search_error",
        "settings",
        "subsequents",
        "undefined_variables",
        "variable_resolver",
    },
    5: {
        "assertions",
        "backticks",
        "booleans",
        "comparison",
        "conditional",
        "datetime",
        "directories",
        "enclosure",
        "equals",
        "evaluate",
        "evaluator",
        "format_string",
        "function",
        "function_definitions",
        "functions",
        "lazy",
        "list_literals",
        "logical_operators",
        "negation",
        "quote",
        "range_ext",
        "recursion_limit",
        "regexes",
        "scope",
        "shadowing_parameters",
        "slash_operator",
        "string",
        "unindent",
        "value",
        "which_function",
    },
    6: {
        "alias_style",
        "changelog",
        "dump",
        "groups",
        "init",
        "json",
        "list",
        "man",
        "readme",
        "show",
        "subcommand",
        "summary",
        "usage",
        "version",
    },
    7: {
        "allow_missing",
        "config",
        "dotenv",
        "invocation_directory",
        "invocation_parser",
        "justfile",
        "justfile_from_stdin",
        "options",
        "overrides",
        "positional",
        "positional_arguments",
        "request",
        "resolve",
        "shell_expansion",
        "tempdir",
        "working_directory",
    },
    8: {
        "assignment",
        "byte_order_mark",
        "command",
        "constants",
        "default",
        "delimiters",
        "error_messages",
        "examples",
        "explain",
        "executor",
        "export",
        "extension",
        "guards",
        "ignore_comments",
        "indentation",
        "interpolation",
        "keyword",
        "line_prefixes",
        "lists",
        "multibyte_char",
        "newline_escape",
        "no_aliases",
        "no_cd",
        "no_exit_message",
        "private",
        "quiet",
        "run",
        "script",
        "shebang",
        "shell",
        "shell_kind",
        "signal",
        "signals",
        "style",
        "timestamps",
        "unexport",
        "unstable",
    },
    9: {"cache", "clean"},
    10: {"choose", "confirm", "count", "edit", "parallel"},
}


PHASE_TEST_ANCHORS = {
    3: {
        "parser": (
            "src/parser/top_level_test.mbt",
            "top-level parser builds assignments aliases settings recipes and imports",
        ),
        "format": (
            "src/formatter/formatter_test.mbt",
            "phase 3 formatter corpus is idempotent across representative grammar",
        ),
        "markdown": (
            "src/formatter/markdown_test.mbt",
            "phase 3 markdown corpus preserves CommonMark fence boundaries",
        ),
        "tangle": (
            "src/formatter/markdown_test.mbt",
            "markdown tangle requires matching fence character and minimum length",
        ),
    },
    4: {
        "semantic": (
            "src/semantic/semantic_test.mbt",
            "compilation exposes ordered symbols and typed settings",
        ),
        "validation": (
            "src/semantic/semantic_test.mbt",
            "semantic validation checks minimum version, dependency arity, and recipe variables",
        ),
        "settings": (
            "src/semantic/semantic_test.mbt",
            "settings and attributes expose complete typed contracts",
        ),
        "loader_search": (
            "src/loader/loader_test.mbt",
            "search ascends to the project ceiling and loads through host",
        ),
        "loader_global": (
            "src/loader/loader_test.mbt",
            "global fallback and stdin loading are explicit",
        ),
        "loader_graph": (
            "src/loader/loader_test.mbt",
            "optional imports are skipped and cycles are reported",
        ),
    },
    5: {
        "pure": (
            "src/builtin/builtin_test.mbt",
            "pure builtins cover string, path, regex and semver contracts",
        ),
        "builtin_collections": (
            "src/builtin/builtin_test.mbt",
            "canonical string and list builtins are deterministic",
        ),
        "effect": (
            "src/evaluator/evaluator_test.mbt",
            "effect context connects fs random clock process terminal and PATH facts",
        ),
        "evaluation": (
            "src/evaluator/evaluator_test.mbt",
            "pure evaluation supports conditions, lists, concatenation and builtins",
        ),
        "lazy": (
            "src/evaluator/evaluator_test.mbt",
            "lazy assignments expose states and redact cycle diagnostics",
        ),
        "scope": (
            "src/evaluator/evaluator_test.mbt",
            "recipe and module scopes implement defaults variadics shadowing and exports",
        ),
        "limits": (
            "src/evaluator/evaluator_test.mbt",
            "evaluation limits reject adversarial depth",
        ),
    },
    6: {
        "init": (
            "src/application/application_test.mbt",
            "init creates the canonical template and refuses overwrite",
        ),
        "list": (
            "src/application/application_test.mbt",
            "list renders docs aliases groups and hides private recipes",
        ),
        "alias_style": (
            "src/application/application_test.mbt",
            "list groups recipes once and supports every upstream alias style",
        ),
        "groups": (
            "src/application/application_test.mbt",
            "groups are deduplicated and Unicode list padding uses display width",
        ),
        "show_usage": (
            "src/application/application_test.mbt",
            "show and usage resolve aliases without executing recipes",
        ),
        "summary": (
            "src/application/application_test.mbt",
            "summary supports sorted and source-order output",
        ),
        "inspect": (
            "src/application/application_test.mbt",
            "dump and JSON inspect are deterministic and schema-pinned",
        ),
        "version": (
            "build_info_test.mbt",
            "release metadata is explicit",
        ),
    },
}


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def phase_for(category: str) -> int:
    matches = [phase for phase, prefixes in PHASE_PREFIXES.items() if category in prefixes]
    if len(matches) != 1:
        raise ValueError(
            f"category {category!r} must have exactly one owner phase, found {matches}"
        )
    return matches[0]


def anchor_for(phase: int, category: str) -> tuple[str, str]:
    """Return the executable family test that owns an upstream category."""
    if phase == 3:
        return PHASE_TEST_ANCHORS[3][category]
    if phase == 4:
        if category in {
            "ceiling",
            "search",
            "search_arguments",
            "search_error",
        }:
            return PHASE_TEST_ANCHORS[4]["loader_search"]
        if category in {"fallback", "global"}:
            return PHASE_TEST_ANCHORS[4]["loader_global"]
        if category in {"imports", "modulepath", "modules"}:
            return PHASE_TEST_ANCHORS[4]["loader_graph"]
        if category in {
            "settings",
            "minimum_version",
            "no_dependencies",
            "os_attributes",
            "attribute",
            "attributes",
            "arg_attribute",
        }:
            return PHASE_TEST_ANCHORS[4]["settings"]
        if category in {
            "alias",
            "allow_duplicate_recipes",
            "allow_duplicate_variables",
            "analyzer",
            "compiler",
            "dependencies",
            "mapped_dependencies",
            "parameters",
            "recipe_resolver",
            "subsequents",
            "undefined_variables",
            "variable_resolver",
        }:
            return PHASE_TEST_ANCHORS[4]["validation"]
        return PHASE_TEST_ANCHORS[4]["semantic"]
    if phase == 5:
        if category in {"datetime", "directories", "which_function"}:
            return PHASE_TEST_ANCHORS[5]["effect"]
        if category in {"functions", "string", "quote", "regexes", "function"}:
            return PHASE_TEST_ANCHORS[5]["pure"]
        if category in {"list_literals", "unindent"}:
            return PHASE_TEST_ANCHORS[5]["builtin_collections"]
        if category == "lazy":
            return PHASE_TEST_ANCHORS[5]["lazy"]
        if category in {"scope", "shadowing_parameters", "function_definitions"}:
            return PHASE_TEST_ANCHORS[5]["scope"]
        if category == "recursion_limit":
            return PHASE_TEST_ANCHORS[5]["limits"]
        return PHASE_TEST_ANCHORS[5]["evaluation"]
    if phase == 6:
        if category in {"init", "subcommand"}:
            return PHASE_TEST_ANCHORS[6]["init"]
        if category == "alias_style":
            return PHASE_TEST_ANCHORS[6]["alias_style"]
        if category == "groups":
            return PHASE_TEST_ANCHORS[6]["groups"]
        if category in {"show", "usage"}:
            return PHASE_TEST_ANCHORS[6]["show_usage"]
        if category == "summary":
            return PHASE_TEST_ANCHORS[6]["summary"]
        if category in {"dump", "json"}:
            return PHASE_TEST_ANCHORS[6]["inspect"]
        if category == "version":
            return PHASE_TEST_ANCHORS[6]["version"]
        return PHASE_TEST_ANCHORS[6]["list"]
    raise ValueError(f"phase {phase} has no executable anchor mapping")


def anchor_exists(repo: Path, anchor: dict[str, str]) -> bool:
    suite = repo / anchor["suite"]
    if not suite.is_file():
        return False
    declaration = re.compile(
        rf'^\s*test\s+"{re.escape(anchor["test_name"])}"\s*\{{',
        re.MULTILINE,
    )
    return declaration.search(suite.read_text(encoding="utf-8")) is not None


def anchor_dict(phase: int, category: str) -> dict[str, str]:
    suite, test_name = anchor_for(phase, category)
    return {"suite": suite, "test_name": test_name}


def build_rows(names: list[str]) -> list[dict[str, object]]:
    rows = []
    for index, name in enumerate(names, start=1):
        category = name.split("::", 1)[0]
        if category == "misc":
            phase = 8
        elif category == "completions":
            phase = 6
        else:
            phase = phase_for(category)

        row: dict[str, object] = {
            "schema_version": 1,
            "id": f"JUST-1.57.0-{index:04d}",
            "upstream_name": name,
            "category": category,
            "owner_phase": phase,
            "tier": "X" if category == "completions" else "A",
            "targets": [],
            "disposition": "planned",
            "evidence": ["docs/PROJECT_PLAN.md"],
            "tracking": f"PROJECT_PLAN_PHASE_{phase}",
        }

        if category == "completions":
            row.update(
                disposition="excluded-completion",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking="ADR-0002",
                reason="Shell completion generation is excluded from the compatibility scope.",
            )
        elif phase == 2 and name == "lexer::tests::presume_error":
            row.update(
                disposition="not-applicable",
                evidence=["compat/phase-2.toml"],
                tracking="MJ-LEX-HARDEN-0001",
                reason="Rust-private helper assertion with no user-observable behavior.",
            )
        elif phase == 2:
            row.update(
                disposition="covered-by",
                targets=["native", "wasm1"],
                evidence=[
                    "compat/phase-2.toml",
                    "src/lexer/upstream_lexer_test.mbt",
                    "src/lexer/hardening_test.mbt",
                ],
                tracking="MJ-LEX-HARDEN-0001",
            )
        elif category in {"changelog", "man", "readme"}:
            row.update(
                tier="X",
                disposition="not-applicable",
                evidence=["docs/adr/0001-product-and-command-name.md"],
                tracking="ADR-0001",
                reason="Upstream product-maintenance output is not part of MoonJust compatibility.",
            )
        elif phase <= 6:
            test_anchor = anchor_dict(phase, category)
            row.update(
                disposition="covered-by",
                targets=["native", "wasm1"],
                evidence=[
                    f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl",
                    test_anchor["suite"],
                    f"docs/PHASE_{phase}_REPORT.md",
                ],
                tracking=f"MJ-PHASE-{phase}-CORPUS",
                test_anchor=test_anchor,
            )
        rows.append(row)
    return rows


def encoded_rows(rows: list[dict[str, object]]) -> str:
    return "".join(
        json.dumps(row, ensure_ascii=True, separators=(",", ":"), sort_keys=True) + "\n"
        for row in rows
    )


def write_case_manifests(root: Path, rows: list[dict[str, object]]) -> None:
    for phase in (3, 4, 5, 6):
        path = root / f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl"
        phase_rows = [
            row
            for row in rows
            if row["owner_phase"] == phase and row["disposition"] == "covered-by"
        ]
        encoded = "".join(
            json.dumps(
                {
                    "schema_version": 1,
                    "case_id": row["id"],
                    "upstream_name": row["upstream_name"],
                    "category": row["category"],
                    "owner_phase": phase,
                    "disposition": row["disposition"],
                    "targets": row["targets"],
                    "suite": row["evidence"][1],
                    "test_anchor": row["test_anchor"],
                    "tracking": row["tracking"],
                },
                ensure_ascii=True,
                separators=(",", ":"),
                sort_keys=True,
            )
            + "\n"
            for row in phase_rows
        )
        path.write_text(encoded, encoding="utf-8")


def validate_case_manifests(root: Path, rows: list[dict[str, object]]) -> None:
    for phase in (3, 4, 5, 6):
        path = root / f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl"
        cases = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
        expected = [
            row
            for row in rows
            if row["owner_phase"] == phase and row["disposition"] == "covered-by"
        ]
        if len(cases) != len(expected):
            raise ValueError(f"Phase {phase} case manifest count changed")
        for case, row in zip(cases, expected):
            if case["case_id"] != row["id"] or case["upstream_name"] != row["upstream_name"]:
                raise ValueError(f"Phase {phase} case manifest is not deterministic")
            if case["disposition"] != "covered-by" or not case["suite"]:
                raise ValueError(f"Phase {phase} case lacks executable evidence")
            if case.get("test_anchor") != row.get("test_anchor"):
                raise ValueError(f"Phase {phase} case anchor differs from test map")


def load_names(path: Path) -> list[str]:
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_LIST_SHA256:
        raise ValueError(f"test-list SHA-256 is {digest}, expected {EXPECTED_LIST_SHA256}")
    names = raw.decode("utf-8").splitlines()
    if len(names) != EXPECTED_COUNT:
        raise ValueError(f"expected {EXPECTED_COUNT} registrations, found {len(names)}")
    if len(set(names)) != len(names):
        raise ValueError("upstream test-list contains duplicate registrations")
    return names


def validate_rows(rows: list[dict[str, object]], names: list[str]) -> None:
    if len(rows) != len(names):
        raise ValueError(f"expected {len(names)} map rows, found {len(rows)}")
    allowed = {
        "ported",
        "differential",
        "covered-by",
        "not-applicable",
        "excluded-completion",
        "unsupported",
        "blocked-platform",
        "unverified",
        "planned",
    }
    for index, (row, name) in enumerate(zip(rows, names), start=1):
        expected_id = f"JUST-1.57.0-{index:04d}"
        if row.get("schema_version") != 1 or row.get("id") != expected_id:
            raise ValueError(f"row {index} has an invalid schema or id")
        if row.get("upstream_name") != name:
            raise ValueError(f"row {expected_id} does not match the pinned test list")
        if row.get("disposition") not in allowed:
            raise ValueError(f"row {expected_id} has an invalid disposition")
        if not isinstance(row.get("owner_phase"), int):
            raise ValueError(f"row {expected_id} has no owner phase")
        if row.get("tier") not in {"A", "B", "W", "X"}:
            raise ValueError(f"row {expected_id} has no valid compatibility tier")
        if not isinstance(row.get("targets"), list):
            raise ValueError(f"row {expected_id} has no target list")
        if not isinstance(row.get("evidence"), list):
            raise ValueError(f"row {expected_id} has no evidence list")
        if not isinstance(row.get("tracking"), str) or not row["tracking"]:
            raise ValueError(f"row {expected_id} has no tracking owner")
        if row.get("owner_phase") in {3, 4, 5, 6} and row["disposition"] == "covered-by":
            anchor = row.get("test_anchor")
            if not isinstance(anchor, dict) or set(anchor) != {"suite", "test_name"}:
                raise ValueError(f"row {expected_id} has no executable test anchor")
            if not all(isinstance(value, str) and value for value in anchor.values()):
                raise ValueError(f"row {expected_id} has an invalid executable test anchor")
            if anchor["suite"] != row["evidence"][1]:
                raise ValueError(f"row {expected_id} anchor suite differs from evidence")
            if not anchor_exists(repository_root(), anchor):
                raise ValueError(
                    f"row {expected_id} points to a missing test declaration "
                    f"{anchor['suite']}::{anchor['test_name']}"
                )
        if row["disposition"] in {"not-applicable", "excluded-completion"} and not row.get(
            "reason"
        ):
            raise ValueError(f"row {expected_id} requires a reason")


def main() -> int:
    root = repository_root()
    default_list = root / "tests/upstream/just-1.57.0/test-list.txt"
    default_map = root / "tests/upstream/just-1.57.0/test-map.jsonl"
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-list", type=Path, default=default_list)
    parser.add_argument("--map", type=Path, default=default_map)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    try:
        names = load_names(args.test_list)
        expected_rows = build_rows(names)
        validate_rows(expected_rows, names)
        expected = encoded_rows(expected_rows)
        if args.write:
            args.map.write_text(expected, encoding="utf-8")
            write_case_manifests(root, expected_rows)
        else:
            actual = args.map.read_text(encoding="utf-8")
            parsed = [json.loads(line) for line in actual.splitlines()]
            validate_rows(parsed, names)
            if actual != expected:
                raise ValueError("test map is not the deterministic generated form")
            validate_case_manifests(root, expected_rows)
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as error:
        print(f"upstream test-map error: {error}", file=sys.stderr)
        return 1

    print(
        f"verified {EXPECTED_COUNT} upstream registrations at {UPSTREAM_COMMIT}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
