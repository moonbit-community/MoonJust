#!/usr/bin/env python3
"""Generate and validate the pinned upstream-test ownership map."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tomllib
from pathlib import Path


UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
MAP_SCHEMA_VERSION = 4
EXPECTED_COUNT = 2417
EXPECTED_LIST_SHA256 = (
    "34773c9c59398fe3ac490aa7239b3c33a7b615159ff59b1e85ddef5e802381d9"
)
CONTRACT_SOURCE_PROVENANCE = {
    "config::tests::dotenv_both_filename_and_path": {
        "path": "src/config.rs",
        "line": 699,
        "file_sha256": "3d7332ce2a6a75380d19d99bb4b35e41d3538976c5f3f9e11ca3e988113d3fa8",
    },
    "config::tests::edit_arguments": {
        "path": "src/config.rs",
        "line": 1257,
        "file_sha256": "3d7332ce2a6a75380d19d99bb4b35e41d3538976c5f3f9e11ca3e988113d3fa8",
    },
    "config::tests::no_cache": {
        "path": "src/config.rs",
        "line": 645,
        "file_sha256": "3d7332ce2a6a75380d19d99bb4b35e41d3538976c5f3f9e11ca3e988113d3fa8",
    },
    "parallel::subsequent_dependencies_run_in_parallel": {
        "path": "tests/parallel.rs",
        "line": 46,
        "file_sha256": "aecd29701b1a97434f3e2ef12f23dac7bac01871c8e3dd432f970c5bc1f3eb44",
    },
    "parallel::dependents_block_on_running_dependencies": {
        "path": "tests/parallel.rs",
        "line": 108,
        "file_sha256": "aecd29701b1a97434f3e2ef12f23dac7bac01871c8e3dd432f970c5bc1f3eb44",
    },
    "parallel::jobs_limits_concurrent_recipes": {
        "path": "tests/parallel.rs",
        "line": 143,
        "file_sha256": "aecd29701b1a97434f3e2ef12f23dac7bac01871c8e3dd432f970c5bc1f3eb44",
    },
    "parallel::prior_dependencies_run_in_parallel": {
        "path": "tests/parallel.rs",
        "line": 6,
        "file_sha256": "aecd29701b1a97434f3e2ef12f23dac7bac01871c8e3dd432f970c5bc1f3eb44",
    },
    "parallel::recipes_up_to_job_limit_run_in_parallel": {
        "path": "tests/parallel.rs",
        "line": 171,
        "file_sha256": "aecd29701b1a97434f3e2ef12f23dac7bac01871c8e3dd432f970c5bc1f3eb44",
    },
    "run::tests::run_can_be_called_more_than_once": {
        "path": "src/run.rs",
        "line": 41,
        "file_sha256": "fe030fce9db0faa6f9a4cd6e3b5cee22fdc8da8ec2f0b682794ba95a0ef9a414",
    },
    "shell_kind::tests::from_str": {
        "path": "src/shell_kind.rs",
        "line": 55,
        "file_sha256": "b46954de1fc8df24669196c7ff1182a45b1b3afc9eca4d245a40fa178b1201b0",
    },
    "subcommand::tests::init_justfile": {
        "path": "src/subcommand.rs",
        "line": 1125,
        "file_sha256": "69a90bd00509e15a83b8c9d60ec1db16692a58e8f468f9e0c3b460960b856f25",
    },
}
NATIVE_SIGNAL_TESTS = {
    "signals::continue_default_excludes_hangup",
    "signals::continue_default_excludes_quit",
    "signals::continue_default_line",
    "signals::continue_default_shebang",
    "signals::continue_explicit_excludes_unlisted",
    "signals::continue_hangup_opt_in",
    "signals::continue_runs_subsequents",
    "signals::infallible_line_clears_caught_signal",
    "signals::interrupt_backtick",
    "signals::interrupt_command",
    "signals::interrupt_line",
    "signals::interrupt_shebang",
    "signals::forwarding",
    "signals::siginfo_prints_current_process",
}

AREA_PREFIXES = {
    "lexer": {"lexer"},
    "parser-formatter": {"format", "markdown", "parser", "tangle"},
    "semantic-loader": {
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
    "evaluator-builtins": {
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
    "query-cli": {
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
    "execution-context": {
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
    "executor": {
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
    "runtime-cache": {"cache", "clean", "parallel"},
    "platform-compatibility": {"choose", "confirm", "count", "edit"},
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

AREA_REPORTS = {
    "parser-formatter": "docs/reports/PHASE_3_REPORT.md",
    "semantic-loader": "docs/reports/PHASE_4_REPORT.md",
    "evaluator-builtins": "docs/reports/PHASE_5_REPORT.md",
    "query-cli": "docs/reports/PHASE_6_REPORT.md",
    "execution-context": "docs/reports/PHASE_7_REPORT.md",
    "executor": "docs/reports/PHASE_8_REPORT.md",
    "runtime-cache": "docs/reports/PHASE_9_REPORT.md",
    "platform-compatibility": "docs/reports/PHASE_10_REPORT.md",
}


RUNTIME_CACHE_DIFFERENCES = {
    "cache::clean_path_removes_empty_entries": (
        "MoonJust never publishes the upstream empty failed-run cache entry and "
        "therefore has no empty entry to remove."
    ),
    "cache::clean_removes_cache_directory": (
        "MoonJust preserves permanent digest lock files and the versioned cache "
        "directory to prevent an unlink/recreate split-lock race."
    ),
}


EXPLICIT_CONTRACT_EVIDENCE = {
    "global::not_macos": (
        "internal/application/application_test.mbt",
        "global context follows Linux XDG lookup and project root",
    ),
    "parallel::dependents_block_on_running_dependencies": (
        "internal/runtime/runtime_test.mbt",
        "contract runtime dependents block on running dependencies",
    ),
    "parallel::jobs_limits_concurrent_recipes": (
        "internal/runtime/runtime_test.mbt",
        "contract runtime jobs limits concurrent recipes",
    ),
    "parallel::prior_dependencies_run_in_parallel": (
        "internal/runtime/runtime_test.mbt",
        "contract runtime prior dependencies run in parallel",
    ),
    "parallel::recipes_up_to_job_limit_run_in_parallel": (
        "internal/runtime/runtime_test.mbt",
        "contract runtime recipes up to job limit run in parallel",
    ),
}


INTERACTIVE_DIFFERENCES = {
    "choose::chooser_selections_are_processed_separately": (
        "Chooser output that names a module recipe is rejected because module-path "
        "execution is not yet part of MoonJust's compilation model."
    ),
    "choose::recipes_in_submodules_can_be_chosen": (
        "Chooser candidates currently contain root recipes only; module recipe "
        "selection remains a registered Tier B difference."
    ),
    "choose::skip_recipes_in_private_modules": (
        "Private-module filtering cannot be independently verified until module "
        "recipe candidates are represented by the chooser."
    ),
    "choose::visit_modules_in_alphabetical_order": (
        "Module recipe candidates are not exposed, so their alphabetical traversal "
        "order is not applicable to the current chooser."
    ),
}


EXECUTOR_UNSUPPORTED_CATEGORIES = {
    "allow_missing": "The --allow-missing execution mode is not implemented.",
    "command": "The upstream --command subcommand is not implemented.",
    "constants": "Unstable justfile constants are not implemented.",
    "error_messages": "Exact upstream legacy diagnostic wording is not a compatibility promise.",
    "explain": "The --explain execution mode is not implemented.",
    "guards": "Guard-line execution semantics are parsed but not implemented.",
    "ignore_comments": "The ignore-comments execution setting is parsed but not implemented.",
    "invocation_parser": "Module-path and trailing-separator invocation forms are not implemented.",
    "justfile": "This upstream Rust integration/helper family lacks one-to-one MoonJust execution evidence.",
    "no_exit_message": "Recipe exit-message suppression and override semantics are not implemented.",
    "options": "Recipe option forwarding through dependencies is not implemented.",
    "positional_arguments": "Positional-arguments environment semantics are parsed but not implemented.",
    "private": "The complete private alias, module, recipe, and variable behavior is not implemented.",
    "request": "The upstream private request testing interface is not a product API.",
    "resolve": "MoonJust delegates executable lookup to the process host and does not implement upstream pre-resolution semantics.",
    "shell_expansion": "Shell-expanded string literals are not implemented.",
    "signals": "Signal forwarding and continue-attribute timing are not implemented.",
    "summary": "Module-aware and unstable summary behavior is not implemented.",
    "working_directory": "Effectful working-directory expressions are not covered by executable compatibility tests.",
}


EXECUTOR_UNSUPPORTED_MARKERS = (
    "submodule",
    "module_alias",
    "module_path",
    "in_module",
    "cross_module",
    "modules_sharing",
    "imports_shared",
    "absent_optional_module",
    "highlight",
    "default_list",
    "no_dependencies",
    "no_deps",
    "one_flag",
    "search_directory",
    "constant",
    "fifo",
    "directory_is_ignored",
    "no_quiet",
)


AREA_TEST_ANCHORS = {
    "parser-formatter": {
        "parser": (
            "internal/parser/top_level_test.mbt",
            "top-level parser builds assignments aliases settings recipes and imports",
        ),
        "format": (
            "internal/formatter/formatter_test.mbt",
            "formatter corpus is idempotent across representative grammar",
        ),
        "markdown": (
            "internal/formatter/markdown_test.mbt",
            "markdown corpus preserves CommonMark fence boundaries",
        ),
        "tangle": (
            "internal/formatter/markdown_test.mbt",
            "markdown tangle requires matching fence character and minimum length",
        ),
    },
    "semantic-loader": {
        "semantic": (
            "internal/semantic/semantic_test.mbt",
            "compilation exposes ordered symbols and typed settings",
        ),
        "validation": (
            "internal/semantic/semantic_test.mbt",
            "semantic validation checks minimum version, dependency arity, and recipe variables",
        ),
        "settings": (
            "internal/semantic/semantic_test.mbt",
            "settings and attributes expose complete typed contracts",
        ),
        "loader_search": (
            "internal/loader/loader_test.mbt",
            "search ascends to the project ceiling and loads through host",
        ),
        "loader_global": (
            "internal/loader/loader_test.mbt",
            "global fallback and stdin loading are explicit",
        ),
        "loader_graph": (
            "internal/loader/loader_test.mbt",
            "optional imports are skipped and cycles are reported",
        ),
    },
    "evaluator-builtins": {
        "pure": (
            "internal/builtin/builtin_test.mbt",
            "pure builtins cover string, path, regex and semver contracts",
        ),
        "builtin_collections": (
            "internal/builtin/builtin_test.mbt",
            "canonical string and list builtins are deterministic",
        ),
        "effect": (
            "internal/evaluator/evaluator_test.mbt",
            "effect context connects fs random clock process terminal and PATH facts",
        ),
        "evaluation": (
            "internal/evaluator/evaluator_test.mbt",
            "pure evaluation supports conditions, lists, concatenation and builtins",
        ),
        "lazy": (
            "internal/evaluator/evaluator_test.mbt",
            "lazy assignments expose states and redact cycle diagnostics",
        ),
        "scope": (
            "internal/evaluator/evaluator_test.mbt",
            "recipe and module scopes implement defaults variadics shadowing and exports",
        ),
        "limits": (
            "internal/evaluator/evaluator_test.mbt",
            "evaluation limits reject adversarial depth",
        ),
    },
    "query-cli": {
        "init": (
            "internal/application/application_test.mbt",
            "init creates the canonical template and refuses overwrite",
        ),
        "list": (
            "internal/application/application_test.mbt",
            "list renders docs aliases groups and hides private recipes",
        ),
        "alias_style": (
            "internal/application/application_test.mbt",
            "list groups recipes once and supports every upstream alias style",
        ),
        "groups": (
            "internal/application/application_test.mbt",
            "groups are deduplicated and Unicode list padding uses display width",
        ),
        "show_usage": (
            "internal/application/application_test.mbt",
            "show and usage resolve aliases without executing recipes",
        ),
        "summary": (
            "internal/application/application_test.mbt",
            "summary supports sorted and source-order output",
        ),
        "inspect": (
            "internal/application/application_test.mbt",
            "dump and JSON inspect are deterministic and schema-pinned",
        ),
        "version": (
            "api/build_info_test.mbt",
            "release metadata is explicit",
        ),
    },
    "execution-context": {
        "dotenv": (
            "internal/environment/environment_test.mbt",
            "dotenv file loading implements path filename precedence and ancestor search",
        ),
        "invocation": (
            "internal/invocation/invocation_test.mbt",
            "long short combined repeatable and terminator options match upstream",
        ),
        "stdin": (
            "internal/application/application_test.mbt",
            "relative justfile and working directory use explicit invocation cwd",
        ),
        "workdir": (
            "internal/workdir/workdir_test.mbt",
            "recipe working-directory overrides settings and no-cd",
        ),
        "cli_environment": (
            "internal/cli/cli_test.mbt",
            "shell arguments and clear flag use last occurrence semantics",
        ),
        "overrides": (
            "internal/application/application_test.mbt",
            "CLI variable overrides reach evaluate and invocation validation",
        ),
        "tempdir": (
            "internal/environment/environment_test.mbt",
            "temporary directory CLI setting and host precedence is lexical",
        ),
    },
    "runtime-cache": {
        "cache_key": (
            "internal/cache/cache_test.mbt",
            "cache key invalidates on body extra inputs and outputs",
        ),
        "cache_runtime": (
            "internal/runtime/runtime_test.mbt",
            "cache miss hit input invalidation and corruption recovery",
        ),
        "cache_outputs": (
            "internal/runtime/runtime_test.mbt",
            "missing cache outputs fail without publishing a manifest",
        ),
        "cache_bypass": (
            "internal/runtime/runtime_test.mbt",
            "no-cache bypasses lookup locks and publication",
        ),
        "cache_verbose": (
            "internal/runtime/runtime_test.mbt",
            "verbose cache diagnostics report stable hits and key material",
        ),
        "cache_gate": (
            "internal/application/application_test.mbt",
            "cache attributes require the explicit unstable gate",
        ),
        "cache_scope": (
            "internal/application/application_test.mbt",
            "cache expressions resolve in recipe scope and require scripts",
        ),
        "cache_clean": (
            "internal/application/application_test.mbt",
            "clean filters recipe and module prefixes",
        ),
        "path_clean": (
            "internal/path/path_test.mbt",
            "Unix paths clean without escaping an absolute root",
        ),
        "parallel_runtime": (
            "internal/runtime/runtime_test.mbt",
            "parallel dependencies use bounded stable concurrency",
        ),
        "parallel_failure": (
            "internal/runtime/runtime_test.mbt",
            "parallel failure selection ignores completion timing",
        ),
        "parallel_subsequent": (
            "internal/runtime/runtime_test.mbt",
            "parallel subsequent dependencies join before completion",
        ),
        "jobs": (
            "internal/application/application_test.mbt",
            "jobs must be a positive integer before execution planning",
        ),
    },
    "executor": {
        "bom": (
            "internal/lexer/lexer_test.mbt",
            "operators, comments, BOM, CRLF, and continued lines",
        ),
        "cli": (
            "internal/cli/cli_test.mbt",
            "CLI validates command conflicts color aliases and verbosity",
        ),
        "dependency": (
            "internal/executor/executor_test.mbt",
            "dependency graph is deterministic and once is keyed by parameter values",
        ),
        "effect": (
            "internal/evaluator/evaluator_test.mbt",
            "configured shell captures stdout and removes exactly one line ending",
        ),
        "environment": (
            "internal/environment/environment_test.mbt",
            "process environment precedence table is complete",
        ),
        "evaluation": (
            "internal/evaluator/evaluator_test.mbt",
            "pure evaluation supports conditions, lists, concatenation and builtins",
        ),
        "lexer": (
            "internal/lexer/lexer_test.mbt",
            "recipe bodies preserve text, prefixes, blank lines, and brace escapes",
        ),
        "invocation": (
            "internal/invocation/invocation_test.mbt",
            "long short combined repeatable and terminator options match upstream",
        ),
        "line": (
            "internal/executor/executor_test.mbt",
            "ordinary line evaluates interpolation and captures exact process request",
        ),
        "output": (
            "internal/executor/executor_test.mbt",
            "quiet discards child streams while verbose timestamp and color force echo",
        ),
        "platform": (
            "internal/executor/executor_test.mbt",
            "shell families preserve representative argv without quoting rewrites",
        ),
        "query": (
            "internal/application/application_test.mbt",
            "list renders docs aliases groups and hides private recipes",
        ),
        "script": (
            "internal/executor/executor_test.mbt",
            "shebang script uses executable temporary path and always cleans it",
        ),
        "semantic": (
            "internal/semantic/semantic_test.mbt",
            "settings and attributes expose complete typed contracts",
        ),
        "signal": (
            "internal/host/fake_host_test.mbt",
            "signal numbers and exit codes preserve the process contract",
        ),
        "signals": (
            "internal/runtime/runtime_test.mbt",
            "continue signals are explicit per recipe and preserve subsequent execution",
        ),
        "dotenv": (
            "internal/environment/environment_test.mbt",
            "dotenv file loading implements path filename precedence and ancestor search",
        ),
        "justfile": (
            "internal/parser/top_level_test.mbt",
            "top-level parser builds assignments aliases settings recipes and imports",
        ),
        "style": (
            "internal/evaluator/evaluator_test.mbt",
            "effect context connects fs random clock process terminal and PATH facts",
        ),
    },
    "platform-compatibility": {
        "choose": (
            "internal/application/application_test.mbt",
            "chooser filters candidates and preserves each selected invocation",
        ),
        "confirm": (
            "internal/application/application_test.mbt",
            "confirmation plan preserves parent-first dependency context and prompts",
        ),
        "edit": (
            "internal/application/application_test.mbt",
            "editor uses visual precedence and opens invalid source from its directory",
        ),
        "list": (
            "internal/application/application_test.mbt",
            "list color highlights doc backticks on stdout",
        ),
    },
}


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def area_for(category: str) -> str:
    matches = [area for area, prefixes in AREA_PREFIXES.items() if category in prefixes]
    if len(matches) != 1:
        raise ValueError(
            f"category {category!r} must have exactly one owner area, found {matches}"
        )
    return matches[0]


def case_owner_override(name: str) -> str | None:
    """Route mixed query CLI categories to the area that owns their prerequisites."""
    category = name.split("::", 1)[0]
    if category not in AREA_PREFIXES["query-cli"]:
        return None
    if name.startswith("completions::"):
        return None
    execution_context_markers = (
        "search_directory",
        "invocation_directory",
        "working_directory",
        "submodule",
        "module",
    )
    if any(marker in name for marker in execution_context_markers):
        return "execution-context"
    if name in {
        "init::alternate_marker",
        "init::parent_dir",
        "init::justfile_name_from_invocation_directory",
        "init::justfile_name_from_search_directory",
        "list::list_invalid_path",
        "list::list_unknown_submodule",
        "show::show_invalid_path",
        "show::show_recipe_at_path",
        "show::show_space_separated_path",
        "summary::depth_first_pre_order",
        "summary::summary_implies_unstable",
        "usage::usage_recipe_in_search_directory",
        "json::dotenv_command",
        "json::dotenv_filename_list",
    }:
        return "execution-context"
    if name == "summary::summary_none":
        return "executor"
    if name in {
        "list::backticks_highlighted",
        "list::doc_above_wide_signature",
        "list::tests::and",
        "list::tests::and_ticked",
        "list::tests::or",
        "list::tests::or_ticked",
        "list::unclosed_backticks",
    }:
        return "platform-compatibility"
    return None


def execution_context_anchor_key(name: str) -> str | None:
    """Return execution context evidence only when the prerequisite model is complete."""
    category = name.split("::", 1)[0]
    if category == "dotenv":
        deferred = (
            "only_runs_in_root_module",
            "variable_in_",
            "::fifo",
            "::directory_is_ignored",
        )
        return None if any(marker in name for marker in deferred) else "dotenv"
    if category == "invocation_directory":
        return "workdir"
    if category == "invocation_parser":
        deferred = ("module", "absent_optional", "trailing_separator", "no_default_recipe")
        return None if any(marker in name for marker in deferred) else "invocation"
    if category == "options":
        deferred = (
            "may_be_used_as_dependency",
            "uses_forwarded_dependency_argument",
        )
        return None if any(marker in name for marker in deferred) else "invocation"
    if category == "justfile_from_stdin":
        return "stdin"
    if category == "tempdir":
        return "tempdir"
    if category == "working_directory":
        deferred = (
            "undefined_variable",
            "backtick",
            "recipe_parameter",
            "shell_function",
        )
        return None if any(marker in name for marker in deferred) else "workdir"
    if category == "overrides" and name in {
        "overrides::invalid_override_path_set",
        "overrides::unknown_override_options",
    }:
        return "overrides"
    if category == "config":
        leaf = name.rsplit("::", 1)[-1]
        if leaf.startswith("set_"):
            return "overrides"
        if leaf.startswith("shell_") or leaf == "shell_set":
            return "cli_environment"
        if leaf.startswith("dotenv_"):
            return "dotenv"
        if leaf.startswith("search_config_"):
            return "workdir"
    return None


def deferred_execution_context_owner(name: str) -> str:
    """Move execution context rows whose observable prerequisite starts in a later area."""
    if "no_cache" in name:
        return "runtime-cache"
    if any(marker in name for marker in ("completions", "changelog", "edit_arguments")):
        return "platform-compatibility"
    return "executor"


def executor_difference_reason(name: str) -> str | None:
    category = name.split("::", 1)[0]
    if category in EXECUTOR_UNSUPPORTED_CATEGORIES:
        return EXECUTOR_UNSUPPORTED_CATEGORIES[category]
    if category in {"examples", "misc"}:
        return (
            "This heterogeneous upstream integration registration has no "
            "one-to-one executable MoonJust evidence and is conservatively "
            "registered as unsupported."
        )
    if category in {"dotenv", "init", "json", "list", "lists", "overrides", "show"}:
        return (
            f"The complete upstream {category} integration surface is not yet "
            "covered by MoonJust's executable compatibility corpus."
        )
    if category == "quiet" and any(marker in name for marker in ("choose_", "edit_", "init_", "show_")):
        return "Quiet-mode interaction with this subcommand is not implemented."
    if category == "run" and any(marker in name for marker in ("one_flag", "time_reports")):
        return "This optional run-mode behavior is not implemented."
    if category == "timestamps" and "invalid_format_string" in name:
        return "MoonJust preserves unknown timestamp directives instead of rejecting them."
    if category == "unstable":
        return "User-defined function unstable gating and per-module propagation are not implemented."
    if any(marker in name for marker in EXECUTOR_UNSUPPORTED_MARKERS):
        return "The required module, search, or optional CLI behavior is not implemented."
    return None


def executor_anchor_key(category: str) -> str:
    if category == "byte_order_mark":
        return "bom"
    if category in {"executor", "script", "shebang"}:
        return "script"
    if category in {"config", "positional"}:
        return "cli"
    if category == "dotenv":
        return "dotenv"
    if category == "invocation_parser":
        return "invocation"
    if category == "justfile":
        return "justfile"
    if category == "signals":
        return "signals"
    if category in {"default", "assignment"}:
        return "semantic"
    if category in {"export", "unexport", "no_cd"}:
        return "environment"
    if category in {"interpolation", "delimiters"}:
        return "evaluation"
    if category in {"newline_escape", "keyword", "multibyte_char", "indentation"}:
        return "lexer"
    if category in {"line_prefixes"}:
        return "line"
    if category in {"quiet", "timestamps"}:
        return "output"
    if category == "style":
        return "style"
    if category in {"run"}:
        return "dependency"
    if category in {"shell", "shell_kind"}:
        return "platform"
    if category in {"signal"}:
        return "signal"
    if category in {"groups", "no_aliases", "usage"}:
        return "query"
    raise ValueError(f"executor category {category!r} lacks a conservative classification")


def platform_anchor_key(name: str) -> str:
    category = name.split("::", 1)[0]
    if category == "config":
        return "edit"
    return category


def anchor_for(area: str, category: str, name: str | None = None) -> tuple[str, str]:
    """Return the executable family test that owns an upstream category."""
    if area == "parser-formatter":
        return AREA_TEST_ANCHORS["parser-formatter"][category]
    if area == "semantic-loader":
        if category in {
            "ceiling",
            "search",
            "search_arguments",
            "search_error",
        }:
            return AREA_TEST_ANCHORS["semantic-loader"]["loader_search"]
        if category in {"fallback", "global"}:
            return AREA_TEST_ANCHORS["semantic-loader"]["loader_global"]
        if category in {"imports", "modulepath", "modules"}:
            return AREA_TEST_ANCHORS["semantic-loader"]["loader_graph"]
        if category in {
            "settings",
            "minimum_version",
            "no_dependencies",
            "os_attributes",
            "attribute",
            "attributes",
            "arg_attribute",
        }:
            return AREA_TEST_ANCHORS["semantic-loader"]["settings"]
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
            return AREA_TEST_ANCHORS["semantic-loader"]["validation"]
        return AREA_TEST_ANCHORS["semantic-loader"]["semantic"]
    if area == "evaluator-builtins":
        if category in {"datetime", "directories", "which_function"}:
            return AREA_TEST_ANCHORS["evaluator-builtins"]["effect"]
        if category in {"functions", "string", "quote", "regexes", "function"}:
            return AREA_TEST_ANCHORS["evaluator-builtins"]["pure"]
        if category in {"list_literals", "unindent"}:
            return AREA_TEST_ANCHORS["evaluator-builtins"]["builtin_collections"]
        if category == "lazy":
            return AREA_TEST_ANCHORS["evaluator-builtins"]["lazy"]
        if category in {"scope", "shadowing_parameters", "function_definitions"}:
            return AREA_TEST_ANCHORS["evaluator-builtins"]["scope"]
        if category == "recursion_limit":
            return AREA_TEST_ANCHORS["evaluator-builtins"]["limits"]
        return AREA_TEST_ANCHORS["evaluator-builtins"]["evaluation"]
    if area == "query-cli":
        if category in {"init", "subcommand"}:
            return AREA_TEST_ANCHORS["query-cli"]["init"]
        if category == "alias_style":
            return AREA_TEST_ANCHORS["query-cli"]["alias_style"]
        if category == "groups":
            return AREA_TEST_ANCHORS["query-cli"]["groups"]
        if category in {"show", "usage"}:
            return AREA_TEST_ANCHORS["query-cli"]["show_usage"]
        if category == "summary":
            return AREA_TEST_ANCHORS["query-cli"]["summary"]
        if category in {"dump", "json"}:
            return AREA_TEST_ANCHORS["query-cli"]["inspect"]
        if category == "version":
            return AREA_TEST_ANCHORS["query-cli"]["version"]
        return AREA_TEST_ANCHORS["query-cli"]["list"]
    if area == "execution-context" and name is not None:
        key = execution_context_anchor_key(name)
        if key is not None:
            return AREA_TEST_ANCHORS["execution-context"][key]
    if area == "runtime-cache" and name is not None:
        if category == "parallel":
            if name.endswith("zero_jobs_is_an_error"):
                return AREA_TEST_ANCHORS["runtime-cache"]["jobs"]
            if name.endswith("parallel_dependencies_report_errors"):
                return AREA_TEST_ANCHORS["runtime-cache"]["parallel_failure"]
            if name.endswith("subsequent_dependencies_run_in_parallel"):
                return AREA_TEST_ANCHORS["runtime-cache"]["parallel_subsequent"]
            return AREA_TEST_ANCHORS["runtime-cache"]["parallel_runtime"]
        if category == "clean":
            return AREA_TEST_ANCHORS["runtime-cache"]["path_clean"]
        if category == "config":
            return AREA_TEST_ANCHORS["runtime-cache"]["cache_bypass"]
        if "clean_" in name:
            return AREA_TEST_ANCHORS["runtime-cache"]["cache_clean"]
        if name.endswith("cache_attribute_is_unstable"):
            return AREA_TEST_ANCHORS["runtime-cache"]["cache_gate"]
        if any(marker in name for marker in ("requires_script", "variables_are_resolved", "expression_evaluated")):
            return AREA_TEST_ANCHORS["runtime-cache"]["cache_scope"]
        if any(marker in name for marker in ("missing_output_after_run", "dry_run_skips_output")):
            return AREA_TEST_ANCHORS["runtime-cache"]["cache_outputs"]
        if "no_cache" in name:
            return AREA_TEST_ANCHORS["runtime-cache"]["cache_bypass"]
        if any(marker in name for marker in ("verbose_message", "prints_cache_key")):
            return AREA_TEST_ANCHORS["runtime-cache"]["cache_verbose"]
        if any(marker in name for marker in ("body_change", "environment_invalidates", "extension_invalidates", "extra_invalidates", "interpreter_invalidates", "positional_arguments", "working_directory_invalidates")):
            return AREA_TEST_ANCHORS["runtime-cache"]["cache_key"]
        return AREA_TEST_ANCHORS["runtime-cache"]["cache_runtime"]
    if area == "executor":
        return AREA_TEST_ANCHORS["executor"][executor_anchor_key(category)]
    if area == "platform-compatibility" and name is not None:
        key = platform_anchor_key(name)
        if key == "list":
            if name == "list::doc_above_wide_signature":
                return (
                    "internal/application/application_test.mbt",
                    "list places wide signature documentation above",
                )
            if "::tests::" in name:
                return (
                    "internal/application/width_wbtest.mbt",
                    "human-readable lists use upstream conjunctions and ticks",
                )
        if key == "choose":
            if name in {"choose::cancelled_by_user", "choose::chooser_signal_exit_code_is_propagated"}:
                return (
                    "internal/application/application_test.mbt",
                    "chooser cancellation succeeds and signals preserve exit status",
                )
            if name == "choose::status_error":
                return (
                    "internal/application/application_test.mbt",
                    "chooser nonzero status is propagated",
                )
            if name == "choose::invoke_error_function":
                return (
                    "internal/application/application_test.mbt",
                    "interactive invocation and exit failures retain context",
                )
        if key == "edit":
            if name in {"edit::invoke_error", "edit::status_error"}:
                return (
                    "internal/application/application_test.mbt",
                    "interactive invocation and exit failures retain context",
                )
            if name == "edit::editor_precedence":
                return (
                    "internal/application/application_test.mbt",
                    "editor falls back through EDITOR and vim",
                )
        if key == "confirm" and any(
            marker in name
            for marker in ("dump", "format", "too_many", "argument")
        ):
            return (
                "internal/application/application_test.mbt",
                "confirm attributes format and reject excess prompt arguments",
            )
        return AREA_TEST_ANCHORS["platform-compatibility"][key]
    raise ValueError(f"area {area} has no executable anchor mapping")


def anchor_exists(repo: Path, anchor: dict[str, str]) -> bool:
    suite = repo / anchor["suite"]
    if not suite.is_file():
        return False
    declaration = re.compile(
        rf'^\s*(?:async\s+)?test\s+"{re.escape(anchor["test_name"])}"\s*\{{',
        re.MULTILINE,
    )
    return declaration.search(suite.read_text(encoding="utf-8")) is not None


def anchor_dict(area: str, category: str, name: str | None = None) -> dict[str, str]:
    suite, test_name = anchor_for(area, category, name)
    return {"suite": suite, "test_name": test_name}


def build_rows(names: list[str]) -> list[dict[str, object]]:
    generated_contract_path = (
        repository_root()
        / "tests/upstream/just-1.57.0/contract-cases.jsonl"
    )
    generated_contracts: dict[str, dict[str, object]] = {}
    for case in map(
        json.loads,
        generated_contract_path.read_text(encoding="utf-8").splitlines(),
    ):
        case_id = case.get("case_id")
        if not isinstance(case_id, str) or case_id in generated_contracts:
            raise ValueError(f"generated contract has a duplicate or invalid id: {case_id}")
        if case.get("schema_version") != 1:
            raise ValueError(f"generated contract schema changed for {case_id}")
        generated_contracts[case_id] = case
    differential_manifest = tomllib.loads(
        (repository_root() / "tests/differential/cases.toml").read_text(
            encoding="utf-8"
        )
    )
    differential_evidence: dict[str, str] = {}
    for case in differential_manifest.get("case", []):
        case_id = case["id"]
        for upstream_test in case.get("upstream_tests", []):
            if upstream_test in differential_evidence:
                raise ValueError(
                    f"upstream test {upstream_test!r} is claimed by multiple differential cases"
                )
            differential_evidence[upstream_test] = case_id
    harness_path = (
        repository_root()
        / "tests/upstream/just-1.57.0/harness-results.jsonl"
    )
    harness_evidence: set[str] = set()
    legacy_diagnostic_evidence: set[str] = set()
    for recorded in map(
        json.loads, harness_path.read_text(encoding="utf-8").splitlines()
    ):
        if recorded.get("schema_version") == 4:
            classifications = {
                recorded.get("native"),
                recorded.get("wasm1"),
            }
            if (
                recorded.get("official") == "passed"
                and recorded.get("disposition")
                in {"exact", "diagnostic-exact"}
                and classifications <= {"exact", "diagnostic-exact"}
            ):
                harness_evidence.add(recorded["upstream_name"])
        elif recorded.get("disposition") == "verified-differential" and (
            recorded.get("official") == "passed"
            and recorded.get("native") == "passed"
            and recorded.get("wasm1") == "passed"
        ):
            harness_evidence.add(recorded["upstream_name"])
        elif recorded.get("disposition") == "verified-differential" and (
            recorded.get("official") == "passed"
            and "diagnostic-style"
            in {recorded.get("native"), recorded.get("wasm1")}
        ):
            legacy_diagnostic_evidence.add(recorded["upstream_name"])
    rows = []
    used_generated_contracts: set[str] = set()
    for index, name in enumerate(names, start=1):
        category = name.split("::", 1)[0]
        override = case_owner_override(name)
        if override is not None:
            area = override
        elif category == "misc":
            area = "executor"
        elif category == "completions":
            area = "query-cli"
        else:
            area = area_for(category)

        if area == "execution-context" and execution_context_anchor_key(name) is None:
            area = deferred_execution_context_owner(name)

        row: dict[str, object] = {
            "schema_version": MAP_SCHEMA_VERSION,
            "id": f"JUST-1.57.0-{index:04d}",
            "upstream_name": name,
            "category": category,
            "owner_area": area,
            "scope": (
                "excluded-completion"
                if category == "completions"
                else "compatibility"
            ),
            "targets": [],
            "disposition": "unverified",
            "evidence": ["docs/PROJECT_PLAN.md"],
            "tracking": f"PROJECT_PLAN_AREA_{area.upper().replace('-', '_')}",
            "reason": "No executable compatibility evidence is registered.",
        }

        if category == "completions":
            row.update(
                disposition="excluded-completion",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking="ADR-0002",
                reason="Shell completion generation is excluded from the compatibility scope.",
            )
        elif area == "lexer" and name == "lexer::tests::presume_error":
            row.update(
                scope="upstream-internal",
                disposition="not-applicable",
                evidence=["compat/lexer.toml"],
                tracking=f"MJ-CONTRACT-{index:04d}",
                reason="Rust-private helper assertion with no user-observable behavior.",
            )
        elif area == "lexer":
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    "compat/lexer.toml",
                    "internal/lexer/upstream_lexer_test.mbt",
                    "internal/lexer/hardening_test.mbt",
                ],
                tracking="MJ-LEX-HARDEN-0001",
                test_anchor={
                    "suite": "internal/lexer/upstream_lexer_test.mbt",
                    "test_name": "just 1.57.0 key token oracle corpus",
                },
                contract_case="MJ-CONTRACT::internal/lexer/upstream_lexer_test.mbt::just 1.57.0 key token oracle corpus",
            )
        elif category in {"changelog", "man", "readme"}:
            row.update(
                scope="product-identity",
                disposition="not-applicable",
                evidence=["docs/adr/0001-product-and-command-name.md"],
                tracking="ADR-0001",
                reason="Upstream product-maintenance output is not part of MoonJust compatibility.",
            )
        elif name in harness_evidence and row["scope"] == "compatibility":
            row.update(
                disposition="verified-differential",
                targets=["native", "wasm1"],
                evidence=[
                    "tests/upstream/just-1.57.0/harness-results.jsonl",
                    "tools/upstream/run_official_harness.py",
                ],
                tracking="MJ-UPSTREAM-HARNESS-1.57.0",
                evidence_case=f"MJ-UPSTREAM-HARNESS::{name}",
            )
        elif name in legacy_diagnostic_evidence:
            row.update(
                disposition="unverified",
                targets=[],
                evidence=[
                    "tests/upstream/just-1.57.0/harness-results.jsonl",
                    "tools/upstream/run_official_harness.py",
                ],
                tracking=f"MJ-DIAGNOSTIC-{index:04d}",
                reason=(
                    "Historical diagnostic-style output is not byte-exact or "
                    "approved semantic compatibility evidence."
                ),
            )
        elif area == "runtime-cache" and name in RUNTIME_CACHE_DIFFERENCES:
            row.update(
                disposition="unsupported",
                targets=["native", "wasm1"],
                evidence=[
                    "docs/adr/0008-cache-format-locking-and-hashing.md",
                    "docs/reports/PHASE_9_REPORT.md",
                ],
                tracking="PROJECT_PLAN_PR-105",
                reason=RUNTIME_CACHE_DIFFERENCES[name],
            )
        elif name in NATIVE_SIGNAL_TESTS:
            test_anchor = anchor_dict(area, category, name)
            row.update(
                disposition="verified-contract",
                targets=(
                    ["native"]
                    if name
                    in {
                        "signals::forwarding",
                        "signals::siginfo_prints_current_process",
                    }
                    else ["native", "wasm1"]
                ),
                evidence=[
                    "tests/upstream/just-1.57.0/executor-cases.jsonl",
                    test_anchor["suite"],
                    "tools/upstream/run_official_harness.py",
                    "docs/reports/PHASE_8_REPORT.md",
                ],
                tracking=f"MJ-CONTRACT-{index:04d}",
                test_anchor=test_anchor,
                contract_case=(
                    f"MJ-CONTRACT::{test_anchor['suite']}::"
                    f"{test_anchor['test_name']}"
                ),
            )
        elif area == "executor" and category in {"examples", "request"}:
            row.update(
                scope="upstream-internal",
                disposition="not-applicable",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking=f"MJ-COMPAT-{index:04d}",
                reason=(
                    "Upstream repository fixture or Rust-private testing interface "
                    "has no user-observable MoonJust behavior."
                ),
            )
        elif area == "executor" and name == "constants::tests::readme_table":
            row.update(
                scope="upstream-internal",
                disposition="not-applicable",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking="ADR-0002",
                reason="Rust-private README table synchronization has no runtime compatibility surface.",
            )
        elif area == "executor":
            test_anchor = anchor_dict(area, category, name)
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    "tests/upstream/just-1.57.0/executor-cases.jsonl",
                    test_anchor["suite"],
                    "docs/reports/PHASE_8_REPORT.md",
                ],
                tracking=f"MJ-CONTRACT-{index:04d}",
                test_anchor=test_anchor,
                contract_case=f"MJ-CONTRACT::{test_anchor['suite']}::{test_anchor['test_name']}",
            )
        elif area == "platform-compatibility" and category == "config" and "completions" in name:
            row.update(
                scope="excluded-completion",
                disposition="excluded-completion",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking="ADR-0002",
                reason="Shell completion generation is excluded from the compatibility scope.",
            )
        elif area == "platform-compatibility" and category == "config" and "changelog" in name:
            row.update(
                scope="product-identity",
                disposition="not-applicable",
                evidence=["docs/adr/0001-product-and-command-name.md"],
                tracking="ADR-0001",
                reason="Upstream product-maintenance output is not part of MoonJust compatibility.",
            )
        elif area == "platform-compatibility" and category == "count":
            row.update(
                scope="upstream-internal",
                disposition="not-applicable",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking=f"MJ-COMPAT-{index:04d}",
                reason="Rust-private count display helper has no user-observable compatibility surface.",
            )
        elif area == "platform-compatibility" and name in INTERACTIVE_DIFFERENCES:
            row.update(
                disposition="unsupported",
                targets=["native", "wasm1"],
                evidence=["docs/PROJECT_PLAN.md"],
                tracking=f"MJ-COMPAT-{index:04d}",
                reason=INTERACTIVE_DIFFERENCES[name],
            )
        elif area == "platform-compatibility":
            test_anchor = anchor_dict(area, category, name)
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    "tests/upstream/just-1.57.0/platform-compatibility-cases.jsonl",
                    test_anchor["suite"],
                    "docs/PROJECT_PLAN.md",
                ],
                tracking=f"MJ-CONTRACT-{index:04d}",
                test_anchor=test_anchor,
                contract_case=f"MJ-CONTRACT::{test_anchor['suite']}::{test_anchor['test_name']}",
            )
        elif area in {
            "parser-formatter",
            "semantic-loader",
            "evaluator-builtins",
            "query-cli",
            "execution-context",
            "runtime-cache",
        } and not (
            area == "execution-context"
            and category == "config"
            and name not in CONTRACT_SOURCE_PROVENANCE
        ):
            test_anchor = anchor_dict(area, category, name)
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    f"tests/upstream/just-1.57.0/{AREA_CASE_MANIFESTS[area]}",
                    test_anchor["suite"],
                    AREA_REPORTS[area],
                ],
                tracking=f"MJ-CONTRACT-{index:04d}",
                test_anchor=test_anchor,
                contract_case=f"MJ-CONTRACT::{test_anchor['suite']}::{test_anchor['test_name']}",
            )
        if row["disposition"] == "verified-contract":
            row.pop("reason", None)
        if name in EXPLICIT_CONTRACT_EVIDENCE:
            suite, test_name = EXPLICIT_CONTRACT_EVIDENCE[name]
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    f"tests/upstream/just-1.57.0/{AREA_CASE_MANIFESTS[area]}",
                    suite,
                    AREA_REPORTS[area],
                ],
                tracking=f"MJ-CONTRACT-{index:04d}",
                test_anchor={"suite": suite, "test_name": test_name},
                contract_case=f"MJ-CONTRACT::{suite}::{test_name}",
            )
            row.pop("reason", None)
        if name in differential_evidence:
            evidence_case = differential_evidence[name]
            row.update(
                disposition="verified-differential",
                targets=["native", "wasm1"],
                evidence=["tests/differential/cases.toml"],
                tracking=evidence_case,
                evidence_case=evidence_case,
            )
            row.pop("reason", None)
            row.pop("test_anchor", None)
            row.pop("contract_case", None)
        elif name in harness_evidence and row["scope"] == "compatibility":
            row.update(
                disposition="verified-differential",
                targets=["native", "wasm1"],
                evidence=[
                    "tests/upstream/just-1.57.0/harness-results.jsonl",
                    "tools/upstream/run_official_harness.py",
                ],
                tracking="MJ-UPSTREAM-HARNESS-1.57.0",
                evidence_case=f"MJ-UPSTREAM-HARNESS::{name}",
            )
            row.pop("reason", None)
            row.pop("test_anchor", None)
            row.pop("contract_case", None)
        generated_contract = generated_contracts.get(row["id"])
        if generated_contract is not None:
            used_generated_contracts.add(row["id"])
            if (
                row["scope"] != "compatibility"
                or generated_contract.get("upstream_name") != name
                or generated_contract.get("owner_area") != area
            ):
                raise ValueError(f"generated contract identity differs for {row['id']}")
            test_anchor = generated_contract.get("test_anchor")
            if not isinstance(test_anchor, dict):
                raise ValueError(f"generated contract has no anchor for {row['id']}")
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    "tests/upstream/just-1.57.0/contract-cases.jsonl",
                    test_anchor["suite"],
                    "tools/upstream/generate_contract_cases.py",
                ],
                tracking=generated_contract["contract_case"],
                test_anchor=test_anchor,
                contract_case=generated_contract["contract_case"],
                upstream_source=generated_contract["upstream_source"],
            )
            row.pop("reason", None)
            row.pop("evidence_case", None)
        rows.append(row)

    if used_generated_contracts != set(generated_contracts):
        unused = sorted(set(generated_contracts) - used_generated_contracts)
        raise ValueError(f"generated contracts are not registered: {unused}")

    anchor_counts: dict[tuple[str, str], int] = {}
    for row in rows:
        if row["disposition"] != "verified-contract":
            continue
        anchor = row["test_anchor"]
        key = (anchor["suite"], anchor["test_name"])
        anchor_counts[key] = anchor_counts.get(key, 0) + 1
    for row in rows:
        if row["disposition"] != "verified-contract":
            continue
        anchor = row["test_anchor"]
        key = (anchor["suite"], anchor["test_name"])
        if anchor_counts[key] > 1:
            row.update(
                disposition="unverified",
                targets=[],
                reason=(
                    "The registered MoonBit test is shared by multiple upstream "
                    "registrations and is not independent compatibility evidence."
                ),
            )
            row.pop("test_anchor", None)
            row.pop("contract_case", None)
    for row in rows:
        if row["disposition"] != "verified-contract":
            continue
        if row.get("upstream_source") is not None:
            continue
        provenance = CONTRACT_SOURCE_PROVENANCE.get(row["upstream_name"])
        if provenance is None:
            raise ValueError(
                f"verified contract lacks pinned upstream source: {row['upstream_name']}"
            )
        row["upstream_source"] = provenance
    return rows


def encoded_rows(rows: list[dict[str, object]]) -> str:
    return "".join(
        json.dumps(row, ensure_ascii=True, separators=(",", ":"), sort_keys=True) + "\n"
        for row in rows
    )


def write_case_manifests(root: Path, rows: list[dict[str, object]]) -> None:
    for area, filename in AREA_CASE_MANIFESTS.items():
        path = root / "tests/upstream/just-1.57.0" / filename
        area_rows = [
            row
            for row in rows
            if row["owner_area"] == area
            and row["disposition"] in {"verified-differential", "verified-contract"}
        ]
        def case_record(row: dict[str, object]) -> dict[str, object]:
            record = {
                "schema_version": MAP_SCHEMA_VERSION,
                "case_id": row["id"],
                "upstream_name": row["upstream_name"],
                "category": row["category"],
                "owner_area": area,
                "disposition": row["disposition"],
                "targets": row["targets"],
                "evidence_case": row.get("evidence_case"),
                "contract_case": row.get("contract_case"),
                "upstream_tests": [row["upstream_name"]],
                "test_anchor": row.get("test_anchor"),
                "tracking": row["tracking"],
            }
            if row.get("upstream_source") is not None:
                record["upstream_source"] = row["upstream_source"]
            return record

        encoded = "".join(
            json.dumps(
                case_record(row),
                ensure_ascii=True,
                separators=(",", ":"),
                sort_keys=True,
            )
            + "\n"
            for row in area_rows
        )
        path.write_text(encoded, encoding="utf-8")


def validate_case_manifests(root: Path, rows: list[dict[str, object]]) -> None:
    for area, filename in AREA_CASE_MANIFESTS.items():
        path = root / "tests/upstream/just-1.57.0" / filename
        cases = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
        expected = [
            row
            for row in rows
            if row["owner_area"] == area
            and row["disposition"] in {"verified-differential", "verified-contract"}
        ]
        if len(cases) != len(expected):
            raise ValueError(f"{area} case manifest count changed")
        for case, row in zip(cases, expected):
            if case["case_id"] != row["id"] or case["upstream_name"] != row["upstream_name"]:
                raise ValueError(f"{area} case manifest is not deterministic")
            if case["disposition"] not in {"verified-differential", "verified-contract"}:
                raise ValueError(f"{area} case lacks executable evidence")
            if case.get("test_anchor") != row.get("test_anchor"):
                raise ValueError(f"{area} case anchor differs from test map")
            if case.get("evidence_case") != row.get("evidence_case"):
                raise ValueError(f"{area} differential case differs from test map")
            if case.get("contract_case") != row.get("contract_case"):
                raise ValueError(f"{area} contract case differs from test map")
            if case.get("upstream_source") != row.get("upstream_source"):
                raise ValueError(f"{area} upstream source differs from test map")
            if case.get("upstream_tests") != [row["upstream_name"]]:
                raise ValueError(f"{area} case lacks explicit upstream registration")


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
        "verified-differential",
        "verified-contract",
        "not-applicable",
        "excluded-completion",
        "unsupported",
        "unverified",
    }
    contract_anchors: set[tuple[str, str]] = set()
    for index, (row, name) in enumerate(zip(rows, names), start=1):
        expected_id = f"JUST-1.57.0-{index:04d}"
        if row.get("schema_version") != MAP_SCHEMA_VERSION or row.get("id") != expected_id:
            raise ValueError(f"row {index} has an invalid schema or id")
        if row.get("upstream_name") != name:
            raise ValueError(f"row {expected_id} does not match the pinned test list")
        if row.get("disposition") not in allowed:
            raise ValueError(f"row {expected_id} has an invalid disposition")
        if row.get("owner_area") not in AREA_PREFIXES:
            raise ValueError(f"row {expected_id} has no owner area")
        if row.get("scope") not in {
            "compatibility",
            "excluded-completion",
            "product-identity",
            "upstream-internal",
        }:
            raise ValueError(f"row {expected_id} has no valid compatibility scope")
        if not isinstance(row.get("targets"), list):
            raise ValueError(f"row {expected_id} has no target list")
        if not isinstance(row.get("evidence"), list):
            raise ValueError(f"row {expected_id} has no evidence list")
        if not isinstance(row.get("tracking"), str) or not row["tracking"]:
            raise ValueError(f"row {expected_id} has no tracking owner")
        if row["disposition"] == "verified-contract":
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
            if not isinstance(row.get("contract_case"), str) or not row["contract_case"]:
                raise ValueError(f"row {expected_id} has no contract case id")
            source = row.get("upstream_source")
            if not isinstance(source, dict) or set(source) != {
                "path",
                "line",
                "file_sha256",
            }:
                raise ValueError(f"row {expected_id} has no pinned upstream source")
            if (
                not isinstance(source["path"], str)
                or not source["path"]
                or not isinstance(source["line"], int)
                or source["line"] < 1
                or not re.fullmatch(r"[0-9a-f]{64}", source["file_sha256"])
            ):
                raise ValueError(f"row {expected_id} has invalid upstream source provenance")
            anchor_key = (anchor["suite"], anchor["test_name"])
            if anchor_key in contract_anchors:
                raise ValueError(
                    f"row {expected_id} reuses contract anchor "
                    f"{anchor['suite']}::{anchor['test_name']}"
                )
            contract_anchors.add(anchor_key)
        if row["disposition"] == "verified-differential":
            evidence_case = row.get("evidence_case")
            if not isinstance(evidence_case, str) or not evidence_case:
                raise ValueError(f"row {expected_id} has no differential case")
        if row["disposition"] in {
            "not-applicable",
            "excluded-completion",
            "unsupported",
            "unverified",
        } and not row.get("reason"):
            raise ValueError(f"row {expected_id} requires a reason")


def main() -> int:
    root = repository_root()
    default_list = root / "tests/upstream/just-1.57.0/test-list.txt"
    default_map = root / "tests/upstream/just-1.57.0/test-map.jsonl"
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-list", type=Path, default=default_list)
    parser.add_argument("--map", type=Path, default=default_map)
    parser.add_argument("--write", action="store_true")
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the generated map and one-to-one case manifests without writing",
    )
    args = parser.parse_args()

    try:
        if args.write and args.check:
            raise ValueError("--write and --check cannot be used together")
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
