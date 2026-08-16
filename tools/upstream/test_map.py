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
MAP_SCHEMA_VERSION = 2
EXPECTED_COUNT = 2417
EXPECTED_LIST_SHA256 = (
    "34773c9c59398fe3ac490aa7239b3c33a7b615159ff59b1e85ddef5e802381d9"
)
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
}

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
    9: {"cache", "clean", "parallel"},
    10: {"choose", "confirm", "count", "edit"},
}


PHASE_9_STORAGE_DIFFERENCES = {
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
        "src/application/application_test.mbt",
        "global context follows Linux XDG lookup and project root",
    ),
}


PHASE_10_INTERACTIVE_DIFFERENCES = {
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


PHASE_8_UNSUPPORTED_CATEGORIES = {
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


PHASE_8_UNSUPPORTED_MARKERS = (
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
    7: {
        "dotenv": (
            "src/environment/environment_test.mbt",
            "dotenv file loading implements path filename precedence and ancestor search",
        ),
        "invocation": (
            "src/invocation/invocation_test.mbt",
            "long short combined repeatable and terminator options match upstream",
        ),
        "stdin": (
            "src/application/application_test.mbt",
            "relative justfile and working directory use explicit invocation cwd",
        ),
        "workdir": (
            "src/workdir/workdir_test.mbt",
            "recipe working-directory overrides settings and no-cd",
        ),
        "cli_environment": (
            "src/cli/cli_test.mbt",
            "shell arguments and clear flag use last occurrence semantics",
        ),
        "overrides": (
            "src/application/application_test.mbt",
            "CLI variable overrides reach evaluate and invocation validation",
        ),
        "tempdir": (
            "src/environment/environment_test.mbt",
            "temporary directory CLI setting and host precedence is lexical",
        ),
    },
    9: {
        "cache_key": (
            "src/cache/cache_test.mbt",
            "cache key invalidates on body extra inputs and outputs",
        ),
        "cache_runtime": (
            "src/runtime/runtime_test.mbt",
            "cache miss hit input invalidation and corruption recovery",
        ),
        "cache_outputs": (
            "src/runtime/runtime_test.mbt",
            "missing cache outputs fail without publishing a manifest",
        ),
        "cache_bypass": (
            "src/runtime/runtime_test.mbt",
            "no-cache bypasses lookup locks and publication",
        ),
        "cache_verbose": (
            "src/runtime/runtime_test.mbt",
            "verbose cache diagnostics report stable hits and key material",
        ),
        "cache_gate": (
            "src/application/application_test.mbt",
            "cache attributes require the explicit unstable gate",
        ),
        "cache_scope": (
            "src/application/application_test.mbt",
            "cache expressions resolve in recipe scope and require scripts",
        ),
        "cache_clean": (
            "src/application/application_test.mbt",
            "clean filters recipe and module prefixes",
        ),
        "path_clean": (
            "src/path/path_test.mbt",
            "Unix paths clean without escaping an absolute root",
        ),
        "parallel_runtime": (
            "src/runtime/runtime_test.mbt",
            "parallel dependencies use bounded stable concurrency",
        ),
        "parallel_failure": (
            "src/runtime/runtime_test.mbt",
            "parallel failure selection ignores completion timing",
        ),
        "parallel_subsequent": (
            "src/runtime/runtime_test.mbt",
            "parallel subsequent dependencies join before completion",
        ),
        "jobs": (
            "src/application/application_test.mbt",
            "jobs must be a positive integer before execution planning",
        ),
    },
    8: {
        "bom": (
            "src/lexer/lexer_test.mbt",
            "operators, comments, BOM, CRLF, and continued lines",
        ),
        "cli": (
            "src/cli/cli_test.mbt",
            "phase 10 CLI validates command conflicts color aliases and verbosity",
        ),
        "dependency": (
            "src/executor/executor_test.mbt",
            "dependency graph is deterministic and once is keyed by parameter values",
        ),
        "effect": (
            "src/evaluator/evaluator_test.mbt",
            "configured shell captures stdout and removes exactly one line ending",
        ),
        "environment": (
            "src/environment/environment_test.mbt",
            "process environment precedence table is complete",
        ),
        "evaluation": (
            "src/evaluator/evaluator_test.mbt",
            "pure evaluation supports conditions, lists, concatenation and builtins",
        ),
        "lexer": (
            "src/lexer/lexer_test.mbt",
            "recipe bodies preserve text, prefixes, blank lines, and brace escapes",
        ),
        "invocation": (
            "src/invocation/invocation_test.mbt",
            "long short combined repeatable and terminator options match upstream",
        ),
        "line": (
            "src/executor/executor_test.mbt",
            "ordinary line evaluates interpolation and captures exact process request",
        ),
        "output": (
            "src/executor/executor_test.mbt",
            "quiet discards child streams while verbose timestamp and color force echo",
        ),
        "platform": (
            "src/executor/executor_test.mbt",
            "shell families preserve representative argv without quoting rewrites",
        ),
        "query": (
            "src/application/application_test.mbt",
            "list renders docs aliases groups and hides private recipes",
        ),
        "script": (
            "src/executor/executor_test.mbt",
            "shebang script uses executable temporary path and always cleans it",
        ),
        "semantic": (
            "src/semantic/semantic_test.mbt",
            "settings and attributes expose complete typed contracts",
        ),
        "signal": (
            "src/host/fake_host_test.mbt",
            "signal numbers and exit codes preserve the process contract",
        ),
        "signals": (
            "src/runtime/runtime_test.mbt",
            "continue signals are explicit per recipe and preserve subsequent execution",
        ),
        "dotenv": (
            "src/environment/environment_test.mbt",
            "dotenv file loading implements path filename precedence and ancestor search",
        ),
        "justfile": (
            "src/parser/top_level_test.mbt",
            "top-level parser builds assignments aliases settings recipes and imports",
        ),
        "style": (
            "src/evaluator/evaluator_test.mbt",
            "effect context connects fs random clock process terminal and PATH facts",
        ),
    },
    10: {
        "choose": (
            "src/application/application_test.mbt",
            "chooser filters candidates and preserves each selected invocation",
        ),
        "confirm": (
            "src/application/application_test.mbt",
            "confirmation plan preserves parent-first dependency context and prompts",
        ),
        "edit": (
            "src/application/application_test.mbt",
            "editor uses visual precedence and opens invalid source from its directory",
        ),
        "list": (
            "src/application/application_test.mbt",
            "phase 10 list color highlights doc backticks on stdout",
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


def case_owner_override(name: str) -> int | None:
    """Route mixed Phase 6 categories to the phase that owns their prerequisites."""
    category = name.split("::", 1)[0]
    if category not in PHASE_PREFIXES[6]:
        return None
    if name.startswith("completions::"):
        return None
    phase_7_markers = (
        "search_directory",
        "invocation_directory",
        "working_directory",
        "submodule",
        "module",
    )
    if any(marker in name for marker in phase_7_markers):
        return 7
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
        return 7
    if name == "summary::summary_none":
        return 8
    if name in {
        "list::backticks_highlighted",
        "list::doc_above_wide_signature",
        "list::tests::and",
        "list::tests::and_ticked",
        "list::tests::or",
        "list::tests::or_ticked",
        "list::unclosed_backticks",
    }:
        return 10
    return None


def phase_7_anchor_key(name: str) -> str | None:
    """Return Phase 7 evidence only when the prerequisite model is complete."""
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


def deferred_phase_7_owner(name: str) -> int:
    """Move Phase 7 rows whose observable prerequisite starts in a later phase."""
    if "no_cache" in name:
        return 9
    if any(marker in name for marker in ("completions", "changelog", "edit_arguments")):
        return 10
    return 8


def phase_8_difference_reason(name: str) -> str | None:
    category = name.split("::", 1)[0]
    if category in PHASE_8_UNSUPPORTED_CATEGORIES:
        return PHASE_8_UNSUPPORTED_CATEGORIES[category]
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
    if any(marker in name for marker in PHASE_8_UNSUPPORTED_MARKERS):
        return "The required module, search, or optional CLI behavior is not implemented."
    return None


def phase_8_anchor_key(category: str) -> str:
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
    raise ValueError(f"Phase 8 category {category!r} lacks a conservative classification")


def phase_10_anchor_key(name: str) -> str:
    category = name.split("::", 1)[0]
    if category == "config":
        return "edit"
    return category


def anchor_for(phase: int, category: str, name: str | None = None) -> tuple[str, str]:
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
    if phase == 7 and name is not None:
        key = phase_7_anchor_key(name)
        if key is not None:
            return PHASE_TEST_ANCHORS[7][key]
    if phase == 9 and name is not None:
        if category == "parallel":
            if name.endswith("zero_jobs_is_an_error"):
                return PHASE_TEST_ANCHORS[9]["jobs"]
            if name.endswith("parallel_dependencies_report_errors"):
                return PHASE_TEST_ANCHORS[9]["parallel_failure"]
            if name.endswith("subsequent_dependencies_run_in_parallel"):
                return PHASE_TEST_ANCHORS[9]["parallel_subsequent"]
            return PHASE_TEST_ANCHORS[9]["parallel_runtime"]
        if category == "clean":
            return PHASE_TEST_ANCHORS[9]["path_clean"]
        if category == "config":
            return PHASE_TEST_ANCHORS[9]["cache_bypass"]
        if "clean_" in name:
            return PHASE_TEST_ANCHORS[9]["cache_clean"]
        if name.endswith("cache_attribute_is_unstable"):
            return PHASE_TEST_ANCHORS[9]["cache_gate"]
        if any(marker in name for marker in ("requires_script", "variables_are_resolved", "expression_evaluated")):
            return PHASE_TEST_ANCHORS[9]["cache_scope"]
        if any(marker in name for marker in ("missing_output_after_run", "dry_run_skips_output")):
            return PHASE_TEST_ANCHORS[9]["cache_outputs"]
        if "no_cache" in name:
            return PHASE_TEST_ANCHORS[9]["cache_bypass"]
        if any(marker in name for marker in ("verbose_message", "prints_cache_key")):
            return PHASE_TEST_ANCHORS[9]["cache_verbose"]
        if any(marker in name for marker in ("body_change", "environment_invalidates", "extension_invalidates", "extra_invalidates", "interpreter_invalidates", "positional_arguments", "working_directory_invalidates")):
            return PHASE_TEST_ANCHORS[9]["cache_key"]
        return PHASE_TEST_ANCHORS[9]["cache_runtime"]
    if phase == 8:
        return PHASE_TEST_ANCHORS[8][phase_8_anchor_key(category)]
    if phase == 10 and name is not None:
        key = phase_10_anchor_key(name)
        if key == "list":
            if name == "list::doc_above_wide_signature":
                return (
                    "src/application/application_test.mbt",
                    "phase 10 list places wide signature documentation above",
                )
            if "::tests::" in name:
                return (
                    "src/application/width_wbtest.mbt",
                    "phase 10 human-readable lists use upstream conjunctions and ticks",
                )
        if key == "choose":
            if name in {"choose::cancelled_by_user", "choose::chooser_signal_exit_code_is_propagated"}:
                return (
                    "src/application/application_test.mbt",
                    "chooser cancellation succeeds and signals preserve exit status",
                )
            if name == "choose::status_error":
                return (
                    "src/application/application_test.mbt",
                    "phase 10 chooser nonzero status is propagated",
                )
            if name == "choose::invoke_error_function":
                return (
                    "src/application/application_test.mbt",
                    "phase 10 interactive invocation and exit failures retain context",
                )
        if key == "edit":
            if name in {"edit::invoke_error", "edit::status_error"}:
                return (
                    "src/application/application_test.mbt",
                    "phase 10 interactive invocation and exit failures retain context",
                )
            if name == "edit::editor_precedence":
                return (
                    "src/application/application_test.mbt",
                    "phase 10 editor falls back through EDITOR and vim",
                )
        if key == "confirm" and any(
            marker in name
            for marker in ("dump", "format", "too_many", "argument")
        ):
            return (
                "src/application/application_test.mbt",
                "phase 10 confirm attributes format and reject excess prompt arguments",
            )
        return PHASE_TEST_ANCHORS[10][key]
    raise ValueError(f"phase {phase} has no executable anchor mapping")


def anchor_exists(repo: Path, anchor: dict[str, str]) -> bool:
    suite = repo / anchor["suite"]
    if not suite.is_file():
        return False
    declaration = re.compile(
        rf'^\s*(?:async\s+)?test\s+"{re.escape(anchor["test_name"])}"\s*\{{',
        re.MULTILINE,
    )
    return declaration.search(suite.read_text(encoding="utf-8")) is not None


def anchor_dict(phase: int, category: str, name: str | None = None) -> dict[str, str]:
    suite, test_name = anchor_for(phase, category, name)
    return {"suite": suite, "test_name": test_name}


def build_rows(names: list[str]) -> list[dict[str, object]]:
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
    harness_evidence = {
        row["upstream_name"]
        for row in map(json.loads, harness_path.read_text(encoding="utf-8").splitlines())
        if row["disposition"] == "verified-differential"
        and row["official"] == "passed"
        and row["native"] in {"passed", "diagnostic-style"}
        and row["wasm1"] in {"passed", "diagnostic-style"}
    }
    rows = []
    for index, name in enumerate(names, start=1):
        category = name.split("::", 1)[0]
        override = case_owner_override(name)
        if override is not None:
            phase = override
        elif category == "misc":
            phase = 8
        elif category == "completions":
            phase = 6
        else:
            phase = phase_for(category)

        if phase == 7 and phase_7_anchor_key(name) is None:
            phase = deferred_phase_7_owner(name)

        row: dict[str, object] = {
            "schema_version": MAP_SCHEMA_VERSION,
            "id": f"JUST-1.57.0-{index:04d}",
            "upstream_name": name,
            "category": category,
            "owner_phase": phase,
            "tier": (
                "B"
                if phase == 10 and category in {"choose", "confirm", "edit", "list"}
                else "X" if category == "completions" else "A"
            ),
            "targets": [],
            "disposition": "unverified",
            "evidence": ["docs/PROJECT_PLAN.md"],
            "tracking": f"PROJECT_PLAN_PHASE_{phase}",
            "reason": "No executable compatibility evidence is registered.",
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
                tracking=f"MJ-CONTRACT-{index:04d}",
                reason="Rust-private helper assertion with no user-observable behavior.",
            )
        elif phase == 2:
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    "compat/phase-2.toml",
                    "src/lexer/upstream_lexer_test.mbt",
                    "src/lexer/hardening_test.mbt",
                ],
                tracking="MJ-LEX-HARDEN-0001",
                test_anchor={
                    "suite": "src/lexer/upstream_lexer_test.mbt",
                    "test_name": "just 1.57.0 key token oracle corpus",
                },
                contract_case="MJ-CONTRACT::src/lexer/upstream_lexer_test.mbt::just 1.57.0 key token oracle corpus",
            )
        elif category in {"changelog", "man", "readme"}:
            row.update(
                tier="X",
                disposition="not-applicable",
                evidence=["docs/adr/0001-product-and-command-name.md"],
                tracking="ADR-0001",
                reason="Upstream product-maintenance output is not part of MoonJust compatibility.",
            )
        elif name in harness_evidence and row["tier"] == "A":
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
        elif phase == 9 and name in PHASE_9_STORAGE_DIFFERENCES:
            row.update(
                disposition="unsupported",
                targets=["native", "wasm1"],
                evidence=[
                    "docs/adr/0008-cache-format-locking-and-hashing.md",
                    "docs/PHASE_9_REPORT.md",
                ],
                tracking="PROJECT_PLAN_PR-105",
                reason=PHASE_9_STORAGE_DIFFERENCES[name],
            )
        elif name == "signals::forwarding":
            row.update(
                tier="X",
                disposition="not-applicable",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking="ADR-0002",
                reason=(
                    "The upstream registration exclusively exercises the excluded "
                    "--request testing interface."
                ),
            )
        elif name == "signals::siginfo_prints_current_process":
            row.update(
                tier="B",
                disposition="unsupported",
                targets=["native"],
                evidence=["docs/PHASE_8_REPORT.md"],
                tracking=f"MJ-COMPAT-{index:04d}",
                reason=(
                    "BSD/macOS SIGINFO process-inventory diagnostics are outside "
                    "the Tier A execution contract."
                ),
            )
        elif name in NATIVE_SIGNAL_TESTS:
            test_anchor = anchor_dict(phase, category, name)
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    "tests/upstream/just-1.57.0/phase-8-cases.jsonl",
                    test_anchor["suite"],
                    "tools/upstream/run_official_harness.py",
                    "docs/PHASE_8_REPORT.md",
                ],
                tracking=f"MJ-CONTRACT-{index:04d}",
                test_anchor=test_anchor,
                contract_case=(
                    f"MJ-CONTRACT::{test_anchor['suite']}::"
                    f"{test_anchor['test_name']}"
                ),
            )
        elif phase == 8 and category in {"examples", "request"}:
            row.update(
                tier="X",
                disposition="not-applicable",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking=f"MJ-COMPAT-{index:04d}",
                reason=(
                    "Upstream repository fixture or Rust-private testing interface "
                    "has no user-observable MoonJust behavior."
                ),
            )
        elif phase == 8 and name == "constants::tests::readme_table":
            row.update(
                tier="X",
                disposition="not-applicable",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking="ADR-0002",
                reason="Rust-private README table synchronization has no runtime compatibility surface.",
            )
        elif phase == 8:
            test_anchor = anchor_dict(phase, category, name)
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    "tests/upstream/just-1.57.0/phase-8-cases.jsonl",
                    test_anchor["suite"],
                    "docs/PHASE_8_REPORT.md",
                ],
                tracking=f"MJ-CONTRACT-{index:04d}",
                test_anchor=test_anchor,
                contract_case=f"MJ-CONTRACT::{test_anchor['suite']}::{test_anchor['test_name']}",
            )
        elif phase == 10 and category == "config" and "completions" in name:
            row.update(
                tier="X",
                disposition="excluded-completion",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking="ADR-0002",
                reason="Shell completion generation is excluded from the compatibility scope.",
            )
        elif phase == 10 and category == "config" and "changelog" in name:
            row.update(
                tier="X",
                disposition="not-applicable",
                evidence=["docs/adr/0001-product-and-command-name.md"],
                tracking="ADR-0001",
                reason="Upstream product-maintenance output is not part of MoonJust compatibility.",
            )
        elif phase == 10 and category == "count":
            row.update(
                tier="X",
                disposition="not-applicable",
                evidence=["docs/adr/0002-compatibility-baseline.md"],
                tracking=f"MJ-COMPAT-{index:04d}",
                reason="Rust-private count display helper has no user-observable compatibility surface.",
            )
        elif phase == 10 and name in PHASE_10_INTERACTIVE_DIFFERENCES:
            row.update(
                disposition="unsupported",
                targets=["native", "wasm1"],
                evidence=["docs/PROJECT_PLAN.md"],
                tracking=f"MJ-COMPAT-{index:04d}",
                reason=PHASE_10_INTERACTIVE_DIFFERENCES[name],
            )
        elif phase == 10:
            test_anchor = anchor_dict(phase, category, name)
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    "tests/upstream/just-1.57.0/phase-10-cases.jsonl",
                    test_anchor["suite"],
                    "docs/PROJECT_PLAN.md",
                ],
                tracking=f"MJ-CONTRACT-{index:04d}",
                test_anchor=test_anchor,
                contract_case=f"MJ-CONTRACT::{test_anchor['suite']}::{test_anchor['test_name']}",
            )
        elif phase <= 7 or phase == 9:
            test_anchor = anchor_dict(phase, category, name)
            row.update(
                disposition="verified-contract",
                targets=["native", "wasm1"],
                evidence=[
                    f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl",
                    test_anchor["suite"],
                    f"docs/PHASE_{phase}_REPORT.md",
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
                    f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl",
                    suite,
                    f"docs/PHASE_{phase}_REPORT.md",
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
        elif name in harness_evidence and row["tier"] == "A":
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
        rows.append(row)
    return rows


def encoded_rows(rows: list[dict[str, object]]) -> str:
    return "".join(
        json.dumps(row, ensure_ascii=True, separators=(",", ":"), sort_keys=True) + "\n"
        for row in rows
    )


def write_case_manifests(root: Path, rows: list[dict[str, object]]) -> None:
    for phase in (3, 4, 5, 6, 7, 8, 9, 10):
        path = root / f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl"
        phase_rows = [
            row
            for row in rows
            if row["owner_phase"] == phase
            and row["disposition"] in {"verified-differential", "verified-contract"}
        ]
        encoded = "".join(
            json.dumps(
                {
                    "schema_version": MAP_SCHEMA_VERSION,
                    "case_id": row["id"],
                    "upstream_name": row["upstream_name"],
                    "category": row["category"],
                    "owner_phase": phase,
                    "disposition": row["disposition"],
                    "targets": row["targets"],
                    "evidence_case": row.get("evidence_case"),
                    "contract_case": row.get("contract_case"),
                    "upstream_tests": [row["upstream_name"]],
                    "test_anchor": row.get("test_anchor"),
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
    for phase in (3, 4, 5, 6, 7, 8, 9, 10):
        path = root / f"tests/upstream/just-1.57.0/phase-{phase}-cases.jsonl"
        cases = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
        expected = [
            row
            for row in rows
            if row["owner_phase"] == phase
            and row["disposition"] in {"verified-differential", "verified-contract"}
        ]
        if len(cases) != len(expected):
            raise ValueError(f"Phase {phase} case manifest count changed")
        for case, row in zip(cases, expected):
            if case["case_id"] != row["id"] or case["upstream_name"] != row["upstream_name"]:
                raise ValueError(f"Phase {phase} case manifest is not deterministic")
            if case["disposition"] not in {"verified-differential", "verified-contract"}:
                raise ValueError(f"Phase {phase} case lacks executable evidence")
            if case.get("test_anchor") != row.get("test_anchor"):
                raise ValueError(f"Phase {phase} case anchor differs from test map")
            if case.get("evidence_case") != row.get("evidence_case"):
                raise ValueError(f"Phase {phase} differential case differs from test map")
            if case.get("contract_case") != row.get("contract_case"):
                raise ValueError(f"Phase {phase} contract case differs from test map")
            if case.get("upstream_tests") != [row["upstream_name"]]:
                raise ValueError(f"Phase {phase} case lacks explicit upstream registration")


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
    for index, (row, name) in enumerate(zip(rows, names), start=1):
        expected_id = f"JUST-1.57.0-{index:04d}"
        if row.get("schema_version") != MAP_SCHEMA_VERSION or row.get("id") != expected_id:
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
