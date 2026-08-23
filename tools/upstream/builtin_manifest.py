#!/usr/bin/env python3
"""Generate the typed builtin evidence manifest."""

from __future__ import annotations

import argparse
import json
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "tests/upstream/just-1.57.0/builtins.jsonl"

NULLARY = {
    "arch", "cache_directory", "config_directory", "config_local_directory",
    "data_directory", "data_local_directory", "executable_directory",
    "home_directory", "invocation_directory", "invocation_directory_native",
    "is_dependency", "just_executable", "just_pid", "just_version", "justfile",
    "justfile_directory", "module_directory", "module_file", "module_path",
    "num_cpus", "num_jobs", "os", "os_family", "recipe_name",
    "runtime_directory", "source_directory", "source_file", "uuid",
}
OPTIONAL_BINARY = {"env", "join_list", "split", "style"}
BINARY = {
    "append", "choose", "env_var_or_default", "prepend", "semver_matches",
    "trim_end_match", "trim_end_matches", "trim_start_match",
    "trim_start_matches",
}
TERNARY = {"replace", "replace_regex"}

CAPABILITIES = {
    "context": {
        "absolute_path", "cache_directory", "config_directory",
        "config_local_directory", "data_directory", "data_local_directory",
        "datetime", "executable_directory", "home_directory",
        "invocation_directory", "invocation_directory_native", "is_dependency",
        "just_executable", "just_pid", "just_version", "justfile",
        "justfile_directory", "module_directory", "module_file", "module_path",
        "num_cpus", "num_jobs", "recipe_name", "runtime_directory", "shell",
        "source_directory", "source_file", "which", "require", "blake3_file",
        "canonicalize", "path_exists", "read", "sha256_file",
    },
    "fs-read": {"blake3_file", "canonicalize", "path_exists", "read", "sha256_file", "which", "require"},
    "environment": {"env", "env_var", "env_var_or_default", "which", "require"},
    "clock": {"datetime", "datetime_utc"},
    "random": {"choose", "uuid"},
    "process": {"shell"},
    "platform": {"arch", "os", "os_family", "which", "require"},
    "terminal": {"style"},
}


def arity(name: str) -> tuple[int, int | None]:
    if name in NULLARY:
        return 0, 0
    if name in OPTIONAL_BINARY:
        return 1, 2
    if name in BINARY:
        return 2, 2
    if name in TERNARY:
        return 3, 3
    if name == "join":
        return 2, None
    if name == "shell":
        return 1, None
    return 1, 1


def capabilities(name: str) -> list[str]:
    return [capability for capability, names in CAPABILITIES.items() if name in names]


def aliases(name: str) -> list[str]:
    if name.endswith("_directory_native"):
        return [name.removesuffix("_directory_native") + "_dir_native"]
    if name.endswith("_directory"):
        return [name.removesuffix("_directory") + "_dir"]
    return []


def rows() -> list[dict[str, object]]:
    manifest = tomllib.loads((ROOT / "compat/builtins.toml").read_text(encoding="utf-8"))
    names = manifest["registry"]["canonical"]
    result = []
    for index, name in enumerate(names, start=1):
        minimum, maximum = arity(name)
        required = capabilities(name)
        suite = "internal/evaluator/evaluator_test.mbt" if required else "internal/builtin/builtin_test.mbt"
        result.append({
            "schema_version": 1,
            "index": index,
            "name": name,
            "min_arguments": minimum,
            "max_arguments": maximum,
            "aliases": aliases(name),
            "purity": "effect" if required else "pure",
            "capabilities": required,
            "targets": ["native", "wasm1"],
            "evidence": [suite, "tests/upstream/just-1.57.0/evaluator-builtins-cases.jsonl"],
            "tracking": f"MJ-BUILTIN-{index:03d}",
        })
    return result


def render() -> str:
    return "".join(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n" for row in rows())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = render()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != expected:
            raise SystemExit("typed builtin manifest is stale; run tools/upstream/builtin_manifest.py")
    else:
        OUTPUT.write_text(expected, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
