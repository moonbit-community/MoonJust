#!/usr/bin/env python3
"""Generate and validate the pinned upstream-test ownership map."""

from __future__ import annotations

import argparse
import hashlib
import json
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
        "clean",
        "dump",
        "edit",
        "examples",
        "explain",
        "groups",
        "init",
        "json",
        "list",
        "lists",
        "man",
        "readme",
        "show",
        "style",
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
        "executor",
        "export",
        "extension",
        "guards",
        "ignore_comments",
        "indentation",
        "interpolation",
        "keyword",
        "line_prefixes",
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
        "timestamps",
        "unexport",
        "unstable",
    },
    9: {"cache"},
    10: {"choose", "confirm", "count", "parallel"},
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
        elif phase <= 5:
            if phase == 3:
                suite = {
                    "parser": "src/parser/corpus_test.mbt",
                    "format": "src/formatter/formatter_test.mbt",
                    "markdown": "src/formatter/markdown_test.mbt",
                    "tangle": "src/formatter/markdown_test.mbt",
                }[category]
            elif phase == 4:
                suite = (
                    "src/loader/loader_test.mbt"
                    if category in {"ceiling", "fallback", "global", "imports", "modulepath", "modules", "search", "search_arguments", "search_error"}
                    else "src/semantic/semantic_test.mbt"
                )
            else:
                suite = (
                    "src/builtin/builtin_test.mbt"
                    if category in {"backticks", "datetime", "directories", "function", "function_definitions", "functions", "quote", "regexes", "string", "which_function"}
                    else "src/evaluator/evaluator_test.mbt"
                )
            row.update(
                disposition="covered-by",
                targets=["native", "wasm1"],
                evidence=[
                    f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl",
                    suite,
                    f"docs/PHASE_{phase}_REPORT.md",
                ],
                tracking=f"MJ-PHASE-{phase}-CORPUS",
            )
        rows.append(row)
    return rows


def encoded_rows(rows: list[dict[str, object]]) -> str:
    return "".join(
        json.dumps(row, ensure_ascii=True, separators=(",", ":"), sort_keys=True) + "\n"
        for row in rows
    )


def write_case_manifests(root: Path, rows: list[dict[str, object]]) -> None:
    for phase in (3, 4, 5):
        path = root / f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl"
        phase_rows = [row for row in rows if row["owner_phase"] == phase]
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
    for phase in (3, 4, 5):
        path = root / f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl"
        cases = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
        expected = [row for row in rows if row["owner_phase"] == phase]
        if len(cases) != len(expected):
            raise ValueError(f"Phase {phase} case manifest count changed")
        for case, row in zip(cases, expected):
            if case["case_id"] != row["id"] or case["upstream_name"] != row["upstream_name"]:
                raise ValueError(f"Phase {phase} case manifest is not deterministic")
            if case["disposition"] != "covered-by" or not case["suite"]:
                raise ValueError(f"Phase {phase} case lacks executable evidence")


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
