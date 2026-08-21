#!/usr/bin/env python3
"""Generate independent parser/lexer contract cases from the pinned Rust source.

The upstream parser and lexer suites use declarative ``test!``/``error!``
macros.  This generator preserves the exact source location and input while
giving every registration its own MoonBit test declaration.  It deliberately
fails for registrations it cannot extract instead of inventing evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
AREAS = {
    "parser-formatter": (
        "parser::tests::",
        "src/parser.rs",
        "internal/parser/upstream_contract_test.mbt",
    ),
    "lexer": (
        "lexer::tests::",
        "src/lexer.rs",
        "internal/lexer/upstream_contract_test.mbt",
    ),
}
TANGLE_SOURCE = "src/tangle.rs"
TANGLE_SUITE = "internal/formatter/upstream_tangle_contract_test.mbt"
CLEAN_SOURCE = "src/clean.rs"
CLEAN_SUITE = "internal/path/upstream_clean_contract_test.mbt"
LIST_SOURCE = "src/list.rs"
LIST_SUITE = "internal/application/upstream_list_contract_wbtest.mbt"
VALUE_SOURCE = "src/value.rs"
VALUE_SUITE = "internal/value/upstream_contract_test.mbt"
UNINDENT_SOURCE = "src/unindent.rs"
UNINDENT_SUITE = "internal/parser/upstream_unindent_contract_wbtest.mbt"
CONFIG_SOURCE = "src/config.rs"
CONFIG_SUITE = "internal/cli/upstream_config_contract_test.mbt"
INVOCATION_SOURCE = "src/invocation_parser.rs"
INVOCATION_SUITE = "internal/invocation/upstream_contract_test.mbt"
CONFIG_CONTRACT_NAMES = {
    "color_never",
    "color_always",
    "color_auto",
    "dry_run_long",
    "dry_run_short",
    "highlight_yes",
    "highlight_no",
    "highlight_no_yes",
    "highlight_no_yes_no",
    "highlight_yes_no",
    "no_cache",
    "no_deps",
    "no_dependencies",
    "unsorted_long",
    "unsorted_short",
    "shell_set",
    "shell_args_set_hyphen",
    "shell_args_set_word",
    "shell_args_set_multiple",
    "shell_args_default",
    "shell_args_set",
    "shell_args_clear",
    "shell_args_clear_and_set",
    "shell_args_set_and_clear",
    "shell_args_set_multiple_and_clear",
    "arguments",
    "overrides",
    "overrides_empty",
    "set_default",
    "set_empty",
    "set_one",
    "set_override",
    "set_two",
    "shell_default",
    "search_config_default",
    "search_config_from_working_directory_and_justfile",
    "search_config_justfile_long",
    "search_config_justfile_short",
    "search_config_justfile_stdin_long",
    "search_config_justfile_stdin_short",
    "search_config_justfile_stdin_with_working_directory",
}
INVOCATION_CONTRACTS = {
    "complex_grouping": {
        "source": "FOO A B='blarg':\n  echo foo: {{A}} {{B}}\n\nBAR X:\n  echo bar: {{X}}\n\nBAZ +Z:\n  echo baz: {{Z}}\n",
        "args": ["BAR", "0", "FOO", "1", "2", "BAZ", "3", "4", "5"],
        "recipes": ["BAR", "FOO", "BAZ"],
        "values": [[ ["0"] ], [ ["1"], ["2"] ], [ ["3", "4", "5"] ]],
    },
    "default_recipe_requires_arguments": {
        "source": "foo bar:",
        "args": [],
        "error_code": "MJ-INV-0002",
        "error_message": "recipe `foo` cannot be used as default recipe since it requires at least 1 argument",
    },
    "long_argument": {
        "source": "[arg('bar', long='bar')]\nfoo bar:\n",
        "args": ["foo", "--bar", "baz"],
        "recipes": ["foo"],
        "values": [[["baz"]]],
    },
    "long_argument_terminator": {
        "source": "[arg('bar', long='bar')]\nfoo baz qux='qux' bar='bar':\n",
        "args": ["foo", "--", "--bar"],
        "recipes": ["foo"],
        "values": [[["--bar"], [], []]],
    },
    "long_argument_with_positional": {
        "source": "[arg('bar', long='bar')]\nfoo baz bar:\n",
        "args": ["foo", "qux", "--bar", "baz"],
        "recipes": ["foo"],
        "values": [[["qux"], ["baz"]]],
    },
    "multiple_unknown": {
        "source": "foo:",
        "args": ["bar", "baz"],
        "error_code": "MJ-INV-0003",
        "error_message": "justfile does not contain recipe `bar`",
    },
    "no_recipes": {
        "source": "",
        "args": [],
        "error_code": "MJ-INV-0001",
        "error_message": "justfile contains no recipes",
    },
    "repeatable_long_option": {
        "source": "[arg('bar', long='bar')]\nfoo +bar:\n",
        "args": ["foo", "--bar", "a", "--bar", "b"],
        "recipes": ["foo"],
        "values": [[["a", "b"]]],
    },
    "single_argument_count_mismatch": {
        "source": "foo bar:",
        "args": ["foo"],
        "error_code": "MJ-INV-0012",
        "error_message": "recipe `foo` got 0 positional arguments but takes 1\nusage:\n    just foo bar",
    },
    "single_no_arguments": {
        "source": "foo:",
        "args": ["foo"],
        "recipes": ["foo"],
        "values": [[]],
    },
    "single_unknown": {
        "source": "foo:",
        "args": ["bar"],
        "error_code": "MJ-INV-0003",
        "error_message": "justfile does not contain recipe `bar`",
    },
    "single_with_argument": {
        "source": "foo bar:",
        "args": ["foo", "baz"],
        "recipes": ["foo"],
        "values": [[["baz"]]],
    },
}


def root() -> Path:
    return Path(__file__).resolve().parents[2]


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def rust_string(block: str, field: str) -> str | None:
    match = re.search(rf"\b{field}:\s*", block)
    if match is None:
        return None
    index = match.end()
    raw = re.match(r"r(#+)?\"", block[index:])
    if raw is not None:
        hashes = raw.group(1) or ""
        start = index + len(raw.group(0))
        end = block.find("\"" + hashes, start)
        if end < 0:
            raise ValueError(f"unterminated raw Rust string for {field}")
        return block[start:end]
    if index >= len(block) or block[index] != '"':
        return None
    index += 1
    value: list[str] = []
    escapes = {
        "n": "\n",
        "r": "\r",
        "t": "\t",
        "0": "\0",
        "\\": "\\",
        '"': '"',
    }
    while index < len(block):
        character = block[index]
        index += 1
        if character == '"':
            return "".join(value)
        if character != "\\":
            value.append(character)
            continue
        if index >= len(block):
            break
        escaped = block[index]
        index += 1
        value.append(escapes.get(escaped, escaped))
    return None


def unindent(text: str) -> str:
    lines = text.splitlines(keepends=True)
    indentation: list[str] = []
    for line in lines:
        if line.strip(" \t\r\n"):
            prefix = re.match(r"[ \t]*", line).group(0)
            indentation.append(prefix)
    common = indentation[0] if indentation else ""
    for prefix in indentation[1:]:
        length = 0
        for left, right in zip(common, prefix):
            if left != right:
                break
            length += 1
        common = common[:length]
    output: list[str] = []
    for index, line in enumerate(lines):
        blank = not line.strip(" \t\r\n")
        first = index == 0
        last = index == len(lines) - 1
        if blank and not first and not last:
            output.append("\r\n" if line.endswith("\r\n") else "\n")
        elif blank:
            continue
        else:
            output.append(line[len(common) :])
    return "".join(output)


def blocks(source: str) -> list[tuple[str, str, int, str]]:
    found: list[tuple[str, str, int, str]] = []
    for macro in ("test", "error", "analysis_error"):
        for match in re.finditer(rf"{macro}!\s*\{{", source):
            index = match.end()
            depth = 1
            quote = False
            raw_end: str | None = None
            escaped = False
            while index < len(source) and depth:
                character = source[index]
                if raw_end is not None:
                    if source.startswith(raw_end, index):
                        index += len(raw_end)
                        raw_end = None
                    else:
                        index += 1
                    continue
                if quote:
                    if escaped:
                        escaped = False
                    elif character == "\\":
                        escaped = True
                    elif character == '"':
                        quote = False
                elif (raw := re.match(r"r(#+)?\"", source[index:])) is not None:
                    raw_end = '"' + (raw.group(1) or "")
                    index += len(raw.group(0))
                    continue
                elif character == '"':
                    quote = True
                elif character == "{":
                    depth += 1
                elif character == "}":
                    depth -= 1
                index += 1
            if depth:
                line = source.count("\n", 0, match.start()) + 1
                raise ValueError(f"unterminated {macro}! block at line {line}")
            body = source[match.end() : index - 1]
            name = re.search(r"\bname:\s*([A-Za-z0-9_]+)", body)
            if name is None:
                continue
            line = source.count("\n", 0, match.start()) + 1
            found.append((name.group(1), macro, line, body))
    return found


def load_rows(path: Path) -> list[dict[str, object]]:
    return list(map(json.loads, path.read_text(encoding="utf-8").splitlines()))


def rust_int(block: str, field: str) -> int:
    match = re.search(rf"\b{field}:\s*(\d+)", block)
    if match is None:
        raise ValueError(f"missing integer Rust field {field}")
    return int(match.group(1))


def rust_literal(block: str, index: int) -> tuple[str, int]:
    while index < len(block) and block[index].isspace():
        index += 1
    raw = re.match(r'r(#+)?"', block[index:])
    if raw is not None:
        hashes = raw.group(1) or ""
        start = index + len(raw.group(0))
        end = block.find('"' + hashes, start)
        if end < 0:
            raise ValueError("unterminated raw Rust string")
        return block[start:end], end + 1 + len(hashes)
    if index >= len(block) or block[index] != '"':
        raise ValueError("expected Rust string literal")
    index += 1
    value: list[str] = []
    escapes = {
        "n": "\n",
        "r": "\r",
        "t": "\t",
        "0": "\0",
        "\\": "\\",
        '"': '"',
    }
    while index < len(block):
        character = block[index]
        index += 1
        if character == '"':
            return "".join(value), index
        if character != "\\":
            value.append(character)
            continue
        if index >= len(block):
            break
        escaped = block[index]
        index += 1
        if escaped == "x" and index + 2 <= len(block):
            value.append(chr(int(block[index : index + 2], 16)))
            index += 2
        else:
            value.append(escapes.get(escaped, escaped))
    raise ValueError("unterminated Rust string literal")


def tangle_cases(source: str, name: str) -> tuple[int, list[tuple[str, str]]]:
    function = re.search(rf"(?m)^  fn {re.escape(name)}\(\) \{{", source)
    if function is None:
        raise ValueError(f"missing tangle test function {name}")
    line = source.count("\n", 0, function.start()) + 1
    end = source.find("\n  }", function.end())
    if end < 0:
        raise ValueError(f"unterminated tangle test function {name}")
    body = source[function.end() : end]
    cases: list[tuple[str, str]] = []
    for call in re.finditer(r"\bcase\s*\(", body):
        first, index = rust_literal(body, call.end())
        while index < len(body) and body[index].isspace():
            index += 1
        if index >= len(body) or body[index] != ",":
            raise ValueError(f"malformed first tangle argument in {name}")
        second, _ = rust_literal(body, index + 1)
        cases.append((unindent(first), unindent(second)))
    if not cases:
        raise ValueError(f"tangle test function {name} has no cases")
    return line, cases


def function_cases(source: str, name: str) -> tuple[int, list[tuple[str, str]]]:
    function = re.search(rf"(?m)^  fn {re.escape(name)}\(\) \{{", source)
    if function is None:
        raise ValueError(f"missing upstream test function {name}")
    line = source.count("\n", 0, function.start()) + 1
    end = source.find("\n  }", function.end())
    if end < 0:
        raise ValueError(f"unterminated upstream test function {name}")
    body = source[function.end() : end]
    cases: list[tuple[str, str]] = []
    for call in re.finditer(r"\bcase\s*\(", body):
        first, index = rust_literal(body, call.end())
        while index < len(body) and body[index].isspace():
            index += 1
        if index >= len(body) or body[index] != ",":
            raise ValueError(f"malformed first case argument in {name}")
        second, _ = rust_literal(body, index + 1)
        cases.append((first, second))
    if not cases:
        raise ValueError(f"upstream test function {name} has no cases")
    return line, cases


def list_cases(source: str, name: str) -> tuple[int, list[dict[str, object]]]:
    function = re.search(rf"(?m)^  fn {re.escape(name)}\(\) \{{", source)
    if function is None:
        raise ValueError(f"missing upstream list test function {name}")
    line = source.count("\n", 0, function.start()) + 1
    end = source.find("\n  }", function.end())
    if end < 0:
        raise ValueError(f"unterminated upstream list test function {name}")
    body = source[function.end() : end]
    results: list[dict[str, object]] = []
    for match in re.finditer(
        r'assert_eq!\s*\(\s*"([^"]*)"\s*,\s*List::(or|and)(_ticked)?\s*\(&\[([^]]*)\]',
        body,
        re.DOTALL,
    ):
        values = [value.strip() for value in match.group(4).split(",") if value.strip()]
        results.append(
            {
                "values": values,
                "conjunction": match.group(2),
                "ticked": match.group(3) is not None,
                "expected": match.group(1),
            }
        )
    if not results:
        raise ValueError(f"upstream list test function {name} has no cases")
    return line, results


def rust_string_array(block: str, index: int) -> tuple[list[str], int]:
    while index < len(block) and block[index].isspace():
        index += 1
    if block.startswith("&[", index):
        index += 2
    elif block.startswith("[", index):
        index += 1
    else:
        raise ValueError("expected Rust string array")
    values: list[str] = []
    while index < len(block):
        while index < len(block) and block[index].isspace():
            index += 1
        if index < len(block) and block[index] == "]":
            return values, index + 1
        value, index = rust_literal(block, index)
        values.append(value)
        while index < len(block) and block[index].isspace():
            index += 1
        if index < len(block) and block[index] == ",":
            index += 1
    raise ValueError("unterminated Rust string array")


def value_function_cases(source: str, name: str) -> tuple[int, list[dict[str, object]]]:
    function = re.search(rf"(?m)^  fn {re.escape(name)}\(\) \{{", source)
    if function is None:
        raise ValueError(f"missing upstream value test function {name}")
    line = source.count("\n", 0, function.start()) + 1
    end = source.find("\n  }", function.end())
    if end < 0:
        raise ValueError(f"unterminated upstream value test function {name}")
    body = source[function.end() : end]
    cases: list[dict[str, object]] = []
    if name == "from_str":
        for match in re.finditer(
            r"Value::from\((?P<value>[^)]*)\)\.elements\(\),\s*(?P<expected>&?\[[^]]*\])",
            body,
            re.DOTALL,
        ):
            value_text = match.group("value").strip()
            if value_text.startswith("String::from("):
                value_text = value_text[len("String::from(") : -1]
            value, _ = rust_literal(value_text, 0)
            expected, _ = rust_string_array(match.group("expected"), 0)
            cases.append({"values": [value], "expected": expected})
        if re.search(r"Value::new\(\)\.elements\(\),\s*\[\]", body):
            cases.append({"values": [], "expected": []})
    else:
        for call in re.finditer(r"\bcase\s*\(\s*(?=&\[)", body):
            values, index = rust_string_array(body, call.end())
            while index < len(body) and body[index].isspace():
                index += 1
            if index >= len(body) or body[index] != ",":
                raise ValueError(f"malformed value case in {name}")
            index += 1
            while index < len(body) and body[index].isspace():
                index += 1
            if name == "is_truthy":
                match = re.match(r"(true|false)\b", body[index:])
                if match is None:
                    raise ValueError(f"malformed truthiness expectation in {name}")
                expected: object = match.group(1) == "true"
            else:
                expected, _ = rust_literal(body, index)
            cases.append({"values": values, "expected": expected})
    if not cases:
        raise ValueError(f"upstream value test function {name} has no cases")
    return line, cases


def unindent_cases(source: str, name: str) -> tuple[int, list[dict[str, object]]]:
    function = re.search(rf"(?m)^  fn {re.escape(name)}\(\) \{{", source)
    if function is None:
        raise ValueError(f"missing upstream unindent test function {name}")
    line = source.count("\n", 0, function.start()) + 1
    end = source.find("\n  }", function.end())
    if end < 0:
        raise ValueError(f"unterminated upstream unindent test function {name}")
    body = source[function.end() : end]
    cases: list[dict[str, object]] = []
    if name in {"unindents"}:
        pattern = r"assert_eq!\s*\(\s*unindent\s*\("
    elif name == "indentations":
        pattern = r"assert_eq!\s*\(\s*indentation\s*\("
    elif name == "commons":
        pattern = r"assert_eq!\s*\(\s*common\s*\("
    else:
        pattern = r"assert!\s*\(\s*(!)?blank\s*\("
    for match in re.finditer(pattern, body):
        if name == "blanks":
            input_value, index = rust_literal(body, match.end())
            expected = match.group(1) is None
            cases.append({"input": input_value, "expected": expected})
            continue
        input_value, index = rust_literal(body, match.end())
        while index < len(body) and body[index].isspace():
            index += 1
        if name in {"unindents", "indentations"} and (index >= len(body) or body[index] != ")"):
            raise ValueError(f"malformed unindent input in {name}")
        if name in {"unindents", "indentations"}:
            index += 1
        while index < len(body) and body[index].isspace():
            index += 1
        if name != "blanks" and (index >= len(body) or body[index] != ","):
            raise ValueError(f"malformed unindent expectation in {name}")
        if name == "commons":
            second, index = rust_literal(body, index + 1)
            while index < len(body) and body[index].isspace():
                index += 1
            if index >= len(body) or body[index] != ")":
                raise ValueError(f"malformed common expectation in {name}")
            index += 1
            while index < len(body) and body[index].isspace():
                index += 1
            if index >= len(body) or body[index] != ",":
                raise ValueError(f"malformed common expectation in {name}")
            expected, _ = rust_literal(body, index + 1)
            cases.append({"input": input_value, "second": second, "expected": expected})
            continue
        expected, _ = rust_literal(body, index + 1)
        cases.append({"input": input_value, "expected": expected})
    if not cases:
        raise ValueError(f"upstream unindent test function {name} has no cases")
    return line, cases


def config_case(source: str, name: str) -> tuple[int, dict[str, object]]:
    by_name = {
        re.search(r"\bname:\s*([A-Za-z0-9_]+)", body).group(1): (line, body)
        for _name, _macro, line, body in blocks(source)
        if re.search(r"\bname:\s*([A-Za-z0-9_]+)", body)
    }
    if name not in by_name:
        raise ValueError(f"missing upstream config test {name}")
    line, body = by_name[name]
    args_match = re.search(r"\bargs:\s*", body)
    if args_match is None:
        raise ValueError(f"config test {name} has no args")
    args, _ = rust_string_array(body, args_match.end())
    flags: dict[str, bool] = {}
    values: dict[str, str] = {}
    if name.startswith("color_"):
        values["color"] = name.removeprefix("color_")
    if name in {"dry_run_long", "dry_run_short"}:
        flags["dry-run"] = True
    if name.startswith("highlight_"):
        enabled = True
        for argument in args:
            if argument == "--highlight":
                enabled = True
            elif argument == "--no-highlight":
                enabled = False
        flags["highlight"] = enabled
        flags["no-highlight"] = not enabled
    if name == "no_cache":
        flags["no-cache"] = True
    if name in {"no_deps", "no_dependencies"}:
        flags["no-deps"] = True
    if name in {"unsorted_long", "unsorted_short"}:
        flags["unsorted"] = True
    if name == "shell_set":
        values["shell"] = "tclsh"
    shell_arguments: list[str] | None = None
    if name.startswith("shell_args_"):
        shell_arguments = [] if "clear" in name else None
        index = 0
        while index < len(args):
            if args[index] == "--clear-shell-args":
                shell_arguments = []
            elif args[index] == "--shell-arg":
                if index + 1 >= len(args):
                    raise ValueError(f"missing shell argument in {name}")
                shell_arguments = (shell_arguments or []) + [args[index + 1]]
                index += 1
            index += 1
    positional: list[str] = args if name == "arguments" else []
    overrides: list[list[str]] = []
    if name.startswith("overrides"):
        for argument in args:
            if "=" in argument and not argument.startswith("--"):
                key, value = argument.split("=", 1)
                overrides.append([key, value])
    if name.startswith("set_"):
        index = 0
        while index < len(args):
            if args[index] == "--set" and index + 2 < len(args):
                overrides.append([args[index + 1], args[index + 2]])
                index += 2
            index += 1
    if name == "search_config_from_working_directory_and_justfile":
        values.update({"working-directory": "foo", "justfile": "bar"})
    elif name in {"search_config_justfile_long", "search_config_justfile_short"}:
        values["justfile"] = "foo"
    elif name in {"search_config_justfile_stdin_long", "search_config_justfile_stdin_short"}:
        values["justfile"] = "-"
    elif name == "search_config_justfile_stdin_with_working_directory":
        values.update({"justfile": "-", "working-directory": "foo"})
    return line, {
        "args": args,
        "flags": flags,
        "values": values,
        "shell_arguments": shell_arguments,
        "positional": positional,
        "overrides": overrides,
    }


def encoded(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def formatted_moonbit(path: Path, content: str) -> str:
    temporary = path.with_name(path.name + ".contract-check.mbt")
    try:
        temporary.write_text(content, encoding="utf-8")
        subprocess.run(
            ["moon", "fmt", str(temporary)],
            cwd=path.parents[1],
            check=True,
            capture_output=True,
            text=True,
        )
        return temporary.read_text(encoding="utf-8")
    finally:
        temporary.unlink(missing_ok=True)


def write_or_check(path: Path, content: str, check: bool) -> None:
    if path.suffix == ".mbt":
        content = formatted_moonbit(path, content)
    if check:
        if not path.is_file() or path.read_text(encoding="utf-8") != content:
            raise ValueError(f"generated contract asset is stale: {path}")
    else:
        path.write_text(content, encoding="utf-8")


def moon_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def render_tests(area: str, cases: list[dict[str, object]]) -> str:
    if area == "parser-formatter":
        header = '''///|
fn contract_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(1700), "upstream-contract", text)
}

///|
fn assert_contract(
  text : String,
  expect_error : Bool,
  expected_offset : Int,
  expected_width : Int,
) -> Unit raise {
  if !expect_error {
    let _ = parse(contract_source(text))
  } else {
    try parse(contract_source(text)) catch {
      error => {
        assert_eq(error.span().start_byte(), expected_offset)
        assert_eq(error.span().length(), expected_width)
      }
    } noraise {
      _ => fail("upstream parser contract unexpectedly succeeded")
    }
  }
}

'''
    else:
        header = '''///|
fn contract_source(text : String) -> @source.Source {
  @source.Source::from_text(@source.SourceId::new(1800), "upstream-contract", text)
}

///|
fn assert_contract(
  text : String,
  expect_error : Bool,
  expected_offset : Int,
  expected_width : Int,
) -> Unit raise {
  if !expect_error {
    let _ = lex(contract_source(text))
  } else {
    try lex(contract_source(text)) catch {
      error => {
        assert_eq(error.span().start_byte(), expected_offset)
        assert_eq(error.span().length(), expected_width)
      }
    } noraise {
      _ => fail("upstream lexer contract unexpectedly succeeded")
    }
  }
}

'''
    tests = []
    for case in cases:
        expectation = case["expected"]
        assert isinstance(expectation, dict)
        span = expectation.get("span", {})
        assert isinstance(span, dict)
        tests.append(
            "///|\n"
            f'test "{case["test_name"]}" {{\n'
            f'  assert_contract({moon_string(str(case["input"]))}, '
            f'{str(expectation["outcome"] == "error").lower()}, '
            f'{int(span.get("offset", -1))}, {int(span.get("width", -1))})\n'
            "}\n"
        )
    return header + "\n".join(tests)


def render_tangle_tests(cases: list[dict[str, object]]) -> str:
    header = '''///|
fn canonical_tangle_source(source : @source.Source) -> String raise {
  let text = source.text()
  if text.is_empty() {
    return ""
  }
  let output = StringBuilder()
  let line_count = source.line_count()
  for line in 1..=line_count {
    let value = source.line_text(line)
    if line == line_count && value.is_empty() && text.has_suffix("\\n") {
      break
    }
    if !value.trim().is_empty() {
      output.write_string(value)
    }
    output.write_char('\\n')
  }
  output.to_string()
}

///|
fn assert_tangle_contract(text : String, expected : String, id : Int) -> Unit raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(id),
    "upstream-tangle-contract.md",
    text,
  )
  assert_eq(canonical_tangle_source(tangle(source).source()), expected)
}

'''
    tests: list[str] = []
    for case_number, case in enumerate(cases):
        inputs = case["input"]
        expectation = case["expected"]
        assert isinstance(inputs, list)
        assert isinstance(expectation, dict)
        outputs = expectation["outputs"]
        assert isinstance(outputs, list)
        rendered_inputs = ", ".join(moon_string(str(value)) for value in inputs)
        rendered_outputs = ", ".join(moon_string(str(value)) for value in outputs)
        tests.append(
            "///|\n"
            f'test "{case["test_name"]}" {{\n'
            f"  let inputs = [{rendered_inputs}]\n"
            f"  let expected = [{rendered_outputs}]\n"
            "  for index, input in inputs {\n"
            f"    assert_tangle_contract(input, expected[index], {2300 + case_number} * 100 + index)\n"
            "  }\n"
            "}\n"
        )
    return header + "\n".join(tests)


def render_clean_tests(cases: list[dict[str, object]]) -> str:
    header = '''///|
fn assert_clean_contract(input : String, expected : String) -> Unit raise {
  let path = PathValue::new(input, Unix)
  assert_eq(path.clean().as_string(), expected)
}

'''
    tests: list[str] = []
    for case in cases:
        expectation = case["expected"]
        assert isinstance(expectation, dict)
        tests.append(
            "///|\n"
            f'test "{case["test_name"]}" {{\n'
            f"  assert_clean_contract({moon_string(str(case['input']))}, "
            f"{moon_string(str(expectation['value']))})\n"
            "}\n"
        )
    return header + "\n".join(tests)


def render_list_tests(cases: list[dict[str, object]]) -> str:
    header = '''///|
fn assert_list_contract(
  values : ArrayView[String],
  conjunction : String,
  ticked : Bool,
  expected : String,
) -> Unit raise {
  assert_eq(format_test_list(values, conjunction, ticked), expected)
}

'''
    tests: list[str] = []
    for case in cases:
        expectation = case["expected"]
        assert isinstance(expectation, dict)
        entries = expectation["cases"]
        assert isinstance(entries, list)
        assertions: list[str] = []
        for entry in entries:
            assert isinstance(entry, dict)
            input_value = entry["input"]
            assert isinstance(input_value, dict)
            values = ", ".join(moon_string(str(value)) for value in input_value["values"])
            assertions.append(
                f"  assert_list_contract([{values}], "
                f"{moon_string(str(input_value['conjunction']))}, "
                f"{str(bool(input_value['ticked'])).lower()}, "
                f"{moon_string(str(entry['value']))})"
            )
        tests.append(
            "///|\n"
            f'test "{case["test_name"]}" {{\n'
            + "\n".join(assertions)
            + "\n"
            "}\n"
        )
    return header + "\n".join(tests)


def render_value_tests(cases: list[dict[str, object]]) -> str:
    header = '''///|
fn value_from_strings(values : ArrayView[String]) -> Value {
  List(values.map(fn(value) { String(value) }))
}

///|
fn assert_value_contract(
  kind : String,
  values : ArrayView[String],
  expected : String,
) -> Unit raise {
  let value = value_from_strings(values)
  match kind {
    "join" => assert_eq(value.join(" "), expected)
    "display" => assert_eq(value.display(), expected)
    _ => fail("unknown value contract")
  }
}

'''
    tests: list[str] = []
    for case in cases:
        expectation = case["expected"]
        assert isinstance(expectation, dict)
        entries = expectation["cases"]
        assert isinstance(entries, list)
        assertions: list[str] = []
        for entry in entries:
            assert isinstance(entry, dict)
            input_value = entry["input"]
            assert isinstance(input_value, dict)
            values = ", ".join(moon_string(str(value)) for value in input_value["values"])
            kind = str(input_value["kind"])
            if kind == "is_truthy":
                assertions.append(
                    f"  assert_eq(value_from_strings([{values}]).truthy(), "
                    f"{str(bool(entry['value'])).lower()})"
                )
            elif kind == "from_str":
                assertions.append(
                    f"  assert_eq(value_from_strings([{values}]).elements(), "
                    f"[{', '.join(moon_string(str(value)) for value in entry['value'])}])"
                )
            else:
                assertions.append(
                    f"  assert_value_contract({moon_string(kind)}, [{values}], "
                    f"{moon_string(str(entry['value']))})"
                )
        tests.append(
            "///|\n"
            f'test "{case["test_name"]}" {{\n'
            + "\n".join(assertions)
            + "\n}\n"
        )
    return header + "\n".join(tests)


def render_unindent_tests(cases: list[dict[str, object]]) -> str:
    header = '''///|
fn assert_unindent_contract(input : String, expected : String) -> Unit raise {
  assert_eq(unindent_string(input), expected)
}

///|
fn assert_indentation_contract(input : String, expected : String) -> Unit raise {
  assert_eq(string_line_indentation(input), expected)
}

///|
fn assert_blank_contract(input : String, expected : Bool) -> Unit raise {
  assert_eq(string_line_is_blank(input), expected)
}

///|
fn assert_common_contract(left : String, right : String, expected : String) -> Unit raise {
  assert_eq(common_string_indentation(left, right), expected)
}

'''
    tests: list[str] = []
    for case in cases:
        expectation = case["expected"]
        assert isinstance(expectation, dict)
        entries = expectation["cases"]
        assert isinstance(entries, list)
        kind = str(expectation["kind"])
        assertions = []
        for entry in entries:
            if kind == "unindents":
                assertions.append(
                    f"  assert_unindent_contract({moon_string(str(entry['input']))}, "
                    f"{moon_string(str(entry['value']))})"
                )
            elif kind == "indentations":
                assertions.append(
                    f"  assert_indentation_contract({moon_string(str(entry['input']))}, "
                    f"{moon_string(str(entry['value']))})"
                )
            elif kind == "blanks":
                assertions.append(
                    f"  assert_blank_contract({moon_string(str(entry['input']))}, "
                    f"{str(bool(entry['value'])).lower()})"
                )
            else:
                assertions.append(
                    f"  assert_common_contract({moon_string(str(entry['input']))}, "
                    f"{moon_string(str(entry['second']))}, "
                    f"{moon_string(str(entry['value']))})"
                )
        tests.append(
            "///|\n"
            f'test "{case["test_name"]}" {{\n'
            + "\n".join(assertions)
            + "\n}\n"
        )
    return header + "\n".join(tests)


def render_config_tests(cases: list[dict[str, object]]) -> str:
    header = '''///|
fn assert_config_contract(
  args : ArrayView[String],
  flags : ArrayView[(String, Bool)],
  values : ArrayView[(String, String)],
  shell_arguments : Array[String]?,
  positional : ArrayView[String],
  overrides : ArrayView[(String, String)],
) -> Unit raise {
  let parsed = @cli.parse_arguments(args, {})
  assert_eq(parsed.command(), RunCommand)
  for flag in flags {
    assert_eq(parsed.flag(flag.0), flag.1)
  }
  for value in values {
    assert_eq(parsed.value(value.0), Some(value.1))
  }
  assert_eq(parsed.shell_arguments(), shell_arguments)
  assert_eq(parsed.positional(), positional)
  assert_eq(parsed.variable_overrides(), overrides)
}

'''
    tests: list[str] = []
    for case in cases:
        expectation = case["expected"]
        assert isinstance(expectation, dict)
        flags = ", ".join(
            f"({moon_string(str(name))}, {str(bool(value)).lower()})"
            for name, value in expectation["flags"].items()
        )
        values = ", ".join(
            f"({moon_string(str(name))}, {moon_string(str(value))})"
            for name, value in expectation["values"].items()
        )
        shell = expectation["shell_arguments"]
        shell_text = (
            "None"
            if shell is None
            else "Some([" + ", ".join(moon_string(str(value)) for value in shell) + "])")
        positional = ", ".join(moon_string(str(value)) for value in expectation["positional"])
        overrides = ", ".join(
            f"({moon_string(str(pair[0]))}, {moon_string(str(pair[1]))})"
            for pair in expectation["overrides"]
        )
        args = ", ".join(moon_string(str(value)) for value in expectation["args"])
        tests.append(
            "///|\n"
            f'test "{case["test_name"]}" {{\n'
            f"  assert_config_contract([{args}], [{flags}], [{values}], {shell_text}, "
            f"[{positional}], [{overrides}])\n"
            "}\n"
        )
    return header + "\n".join(tests)


def render_invocation_tests(cases: list[dict[str, object]]) -> str:
    header = '''///|
fn compile_invocation_contract(text : String) -> @semantic.Compilation raise {
  @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(1900),
      "upstream-invocation-contract",
      text,
    ),
    allow_unstable=true,
  )
}

///|
fn invocation_values(invocation : @invocation.Invocation) -> Array[Array[String]] {
  invocation.arguments().map(fn(value) { value.elements().to_owned() })
}

///|
fn assert_invocation_success(
  source : String,
  args : ArrayView[String],
  recipes : ArrayView[String],
  expected : ArrayView[Array[Array[String]]],
) -> Unit raise {
  let parsed = @invocation.parse_invocations(compile_invocation_contract(source), args)
  assert_eq(parsed.length(), recipes.length())
  for index, recipe in recipes {
    assert_eq(parsed[index].recipe(), recipe)
    assert_eq(invocation_values(parsed[index]), expected[index])
  }
}

///|
fn assert_invocation_error(
  source : String,
  args : ArrayView[String],
  code : String,
  message : String,
) -> Unit raise {
  let compilation = compile_invocation_contract(source)
  try @invocation.parse_invocations(compilation, args) catch {
    error => {
      assert_eq(error.code(), code)
      assert_eq(error.message(), message)
    }
  } noraise {
    _ => fail("invocation contract unexpectedly succeeded")
  }
}

'''
    tests: list[str] = []
    for case in cases:
        test_name = str(case["test_name"])
        args = ", ".join(moon_string(str(value)) for value in case["input"])
        if case["expected"]["outcome"] == "error":
            body = (
                f"  assert_invocation_error({moon_string(str(case['source']))}, "
                f"[{args}], {moon_string(str(case['expected']['code']))}, "
                f"{moon_string(str(case['expected']['message']))})"
            )
        else:
            recipes = ", ".join(moon_string(str(value)) for value in case["expected"]["recipes"])
            def render_values(value: object) -> str:
                if isinstance(value, list):
                    return "[" + ", ".join(render_values(item) for item in value) + "]"
                return moon_string(str(value))

            values = render_values(case["expected"]["values"])
            body = (
                f"  assert_invocation_success({moon_string(str(case['source']))}, "
                f"[{args}], [{recipes}], {values})"
            )
        tests.append("///|\n" f'test "{test_name}" {{\n' + body + "\n}\n")
    return header + "\n".join(tests)


def generate(repo: Path, upstream: Path, output: Path, check: bool) -> int:
    commit = subprocess.run(
        ["git", "-C", str(upstream), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    if commit != UPSTREAM_COMMIT:
        raise ValueError(f"upstream source is {commit}, expected {UPSTREAM_COMMIT}")
    rows = load_rows(repo / "tests/upstream/just-1.57.0/test-map.jsonl")
    prior_cases = load_rows(output) if output.is_file() else []
    generated: list[dict[str, object]] = []
    for area, (prefix, relative_source, suite) in AREAS.items():
        source_path = upstream / relative_source
        source_text = source_path.read_text(encoding="utf-8")
        by_name = {
            name: (macro, line, body)
            for name, macro, line, body in blocks(source_text)
        }
        area_rows = [
            row
            for row in rows
            if row["owner_area"] == area
            and row["scope"] == "compatibility"
            and str(row["upstream_name"]).startswith(prefix)
        ]
        cases: list[dict[str, object]] = []
        for row in area_rows:
            leaf = str(row["upstream_name"]).rsplit("::", 1)[-1]
            extracted = by_name.get(leaf)
            if extracted is None:
                raise ValueError(
                    f"no declarative input extractor for {row['id']} "
                    f"{row['upstream_name']}"
                )
            macro, line, body = extracted
            field = "text" if macro == "test" else "input"
            value = rust_string(body, field)
            if value is None:
                raise ValueError(
                    f"{row['id']} has no literal {field} input from {relative_source}:{line}"
                )
            if area == "parser-formatter" and macro == "test":
                value = unindent(value)
            if area == "lexer" and macro == "test" and "unindent: false" not in body:
                value = unindent(value)
            expected = (
                {"outcome": "success"}
                if macro == "test"
                else {
                    "outcome": "error",
                    "span": {
                        "offset": rust_int(body, "offset"),
                        "width": rust_int(body, "width"),
                    },
                }
            )
            test_name = f"contract {row['id']} {row['upstream_name']}"
            case = {
                "schema_version": 1,
                "case_id": row["id"],
                "upstream_name": row["upstream_name"],
                "owner_area": area,
                "test_name": test_name,
                "test_anchor": {"suite": suite, "test_name": test_name},
                "contract_case": f"MJ-CONTRACT::{row['id']}",
                "upstream_source": {
                    "path": relative_source,
                    "line": line,
                    "file_sha256": sha256(source_path),
                },
                "input": value,
                "input_sha256": sha256_bytes(value.encode("utf-8")),
                "expected": expected,
                "expected_sha256": sha256_bytes(encoded(expected).encode("utf-8")),
            }
            cases.append(case)
            generated.append(case)
        write_or_check(repo / suite, render_tests(area, cases), check)

    tangle_path = upstream / TANGLE_SOURCE
    tangle_source = tangle_path.read_text(encoding="utf-8")
    tangle_rows = [
        row
        for row in rows
        if row["owner_area"] == "parser-formatter"
        and row["scope"] == "compatibility"
        and str(row["upstream_name"]).startswith("tangle::tests::")
    ]
    rendered_tangle_cases: list[dict[str, object]] = []
    for row in tangle_rows:
        leaf = str(row["upstream_name"]).rsplit("::", 1)[-1]
        line, extracted_cases = tangle_cases(tangle_source, leaf)
        inputs = [input_value for input_value, _ in extracted_cases]
        outputs = [expected for _, expected in extracted_cases]
        expected = {
            "outcome": "success",
            "normalizer": "source-map-padding",
            "outputs": outputs,
        }
        test_name = f"contract {row['id']} {row['upstream_name']}"
        case = {
            "schema_version": 1,
            "case_id": row["id"],
            "upstream_name": row["upstream_name"],
            "owner_area": "parser-formatter",
            "test_name": test_name,
            "test_anchor": {"suite": TANGLE_SUITE, "test_name": test_name},
            "contract_case": f"MJ-CONTRACT::{row['id']}",
            "upstream_source": {
                "path": TANGLE_SOURCE,
                "line": line,
                "file_sha256": sha256(tangle_path),
            },
            "input": inputs,
            "input_sha256": sha256_bytes(encoded(inputs).encode("utf-8")),
            "expected": expected,
            "expected_sha256": sha256_bytes(encoded(expected).encode("utf-8")),
        }
        rendered_tangle_cases.append(case)
        generated.append(case)
    write_or_check(
        repo / TANGLE_SUITE,
        render_tangle_tests(rendered_tangle_cases),
        check,
    )

    clean_path = upstream / CLEAN_SOURCE
    clean_source = clean_path.read_text(encoding="utf-8")
    clean_rows = [
        row
        for row in rows
        if row["owner_area"] == "runtime-cache"
        and row["scope"] == "compatibility"
        and str(row["upstream_name"]).startswith("clean::tests::")
    ]
    rendered_clean_cases: list[dict[str, object]] = []
    for row in clean_rows:
        leaf = str(row["upstream_name"]).rsplit("::", 1)[-1]
        line, extracted_cases = function_cases(clean_source, leaf)
        if len(extracted_cases) != 1:
            raise ValueError(f"clean test {leaf} must have exactly one case")
        input_value, output_value = extracted_cases[0]
        expected = {"outcome": "success", "value": output_value}
        test_name = f"contract {row['id']} {row['upstream_name']}"
        case = {
            "schema_version": 1,
            "case_id": row["id"],
            "upstream_name": row["upstream_name"],
            "owner_area": "runtime-cache",
            "test_name": test_name,
            "test_anchor": {"suite": CLEAN_SUITE, "test_name": test_name},
            "contract_case": f"MJ-CONTRACT::{row['id']}",
            "upstream_source": {
                "path": CLEAN_SOURCE,
                "line": line,
                "file_sha256": sha256(clean_path),
            },
            "input": input_value,
            "input_sha256": sha256_bytes(input_value.encode("utf-8")),
            "expected": expected,
            "expected_sha256": sha256_bytes(encoded(expected).encode("utf-8")),
        }
        rendered_clean_cases.append(case)
        generated.append(case)
    write_or_check(repo / CLEAN_SUITE, render_clean_tests(rendered_clean_cases), check)

    list_path = upstream / LIST_SOURCE
    list_source = list_path.read_text(encoding="utf-8")
    list_rows = [
        row
        for row in rows
        if row["owner_area"] == "platform-compatibility"
        and row["scope"] == "compatibility"
        and str(row["upstream_name"]).startswith("list::tests::")
    ]
    rendered_list_cases: list[dict[str, object]] = []
    for row in list_rows:
        leaf = str(row["upstream_name"]).rsplit("::", 1)[-1]
        line, extracted_cases = list_cases(list_source, leaf)
        inputs = [
            {
                "values": [str(value) for value in case["values"]],
                "conjunction": case["conjunction"],
                "ticked": case["ticked"],
            }
            for case in extracted_cases
        ]
        expected = {
            "outcome": "success",
            "cases": [
                {"input": input_value, "value": case["expected"]}
                for input_value, case in zip(inputs, extracted_cases)
            ],
        }
        test_name = f"contract {row['id']} {row['upstream_name']}"
        case = {
            "schema_version": 1,
            "case_id": row["id"],
            "upstream_name": row["upstream_name"],
            "owner_area": "platform-compatibility",
            "test_name": test_name,
            "test_anchor": {"suite": LIST_SUITE, "test_name": test_name},
            "contract_case": f"MJ-CONTRACT::{row['id']}",
            "upstream_source": {
                "path": LIST_SOURCE,
                "line": line,
                "file_sha256": sha256(list_path),
            },
            "input": inputs,
            "input_sha256": sha256_bytes(encoded(inputs).encode("utf-8")),
            "expected": expected,
            "expected_sha256": sha256_bytes(encoded(expected).encode("utf-8")),
        }
        rendered_list_cases.append(case)
        generated.append(case)
    write_or_check(repo / LIST_SUITE, render_list_tests(rendered_list_cases), check)

    value_path = upstream / VALUE_SOURCE
    value_source = value_path.read_text(encoding="utf-8")
    value_rows = [
        row
        for row in rows
        if row["owner_area"] == "evaluator-builtins"
        and row["scope"] == "compatibility"
        and str(row["upstream_name"]).startswith("value::tests::")
        and str(row["upstream_name"]).rsplit("::", 1)[-1]
        in {"join", "display", "is_truthy", "from_str"}
    ]
    rendered_value_cases: list[dict[str, object]] = []
    for row in value_rows:
        leaf = str(row["upstream_name"]).rsplit("::", 1)[-1]
        line, extracted_cases = value_function_cases(value_source, leaf)
        inputs = [
            {
                "values": [str(value) for value in case["values"]],
                "kind": leaf,
            }
            for case in extracted_cases
        ]
        expected = {
            "outcome": "success",
            "cases": [
                {"input": input_value, "value": case["expected"]}
                for input_value, case in zip(inputs, extracted_cases)
            ],
        }
        test_name = f"contract {row['id']} {row['upstream_name']}"
        case = {
            "schema_version": 1,
            "case_id": row["id"],
            "upstream_name": row["upstream_name"],
            "owner_area": "evaluator-builtins",
            "test_name": test_name,
            "test_anchor": {"suite": VALUE_SUITE, "test_name": test_name},
            "contract_case": f"MJ-CONTRACT::{row['id']}",
            "upstream_source": {
                "path": VALUE_SOURCE,
                "line": line,
                "file_sha256": sha256(value_path),
            },
            "input": inputs,
            "input_sha256": sha256_bytes(encoded(inputs).encode("utf-8")),
            "expected": expected,
            "expected_sha256": sha256_bytes(encoded(expected).encode("utf-8")),
        }
        rendered_value_cases.append(case)
        generated.append(case)
    write_or_check(repo / VALUE_SUITE, render_value_tests(rendered_value_cases), check)

    unindent_path = upstream / UNINDENT_SOURCE
    unindent_source = unindent_path.read_text(encoding="utf-8")
    unindent_rows = [
        row
        for row in rows
        if row["owner_area"] == "evaluator-builtins"
        and row["scope"] == "compatibility"
        and str(row["upstream_name"]).startswith("unindent::tests::")
    ]
    rendered_unindent_cases: list[dict[str, object]] = []
    for row in unindent_rows:
        leaf = str(row["upstream_name"]).rsplit("::", 1)[-1]
        line, extracted_cases = unindent_cases(unindent_source, leaf)
        inputs = [case["input"] for case in extracted_cases]
        expected = {
            "outcome": "success",
            "kind": leaf,
            "cases": [
                {
                    "input": input_value,
                    "second": case.get("second"),
                    "value": case["expected"],
                }
                for input_value, case in zip(inputs, extracted_cases)
            ],
        }
        test_name = f"contract {row['id']} {row['upstream_name']}"
        case = {
            "schema_version": 1,
            "case_id": row["id"],
            "upstream_name": row["upstream_name"],
            "owner_area": "evaluator-builtins",
            "test_name": test_name,
            "test_anchor": {"suite": UNINDENT_SUITE, "test_name": test_name},
            "contract_case": f"MJ-CONTRACT::{row['id']}",
            "upstream_source": {
                "path": UNINDENT_SOURCE,
                "line": line,
                "file_sha256": sha256(unindent_path),
            },
            "input": inputs,
            "input_sha256": sha256_bytes(encoded(inputs).encode("utf-8")),
            "expected": expected,
            "expected_sha256": sha256_bytes(encoded(expected).encode("utf-8")),
        }
        rendered_unindent_cases.append(case)
        generated.append(case)
    write_or_check(repo / UNINDENT_SUITE, render_unindent_tests(rendered_unindent_cases), check)

    config_path = upstream / CONFIG_SOURCE
    config_source = config_path.read_text(encoding="utf-8")
    config_rows = [
        row
        for row in rows
        if row["owner_area"] in {"executor", "execution-context"}
        and row["scope"] == "compatibility"
        and str(row["upstream_name"]).startswith("config::tests::")
        and str(row["upstream_name"]).rsplit("::", 1)[-1] in CONFIG_CONTRACT_NAMES
    ]
    rendered_config_cases: list[dict[str, object]] = []
    for row in config_rows:
        leaf = str(row["upstream_name"]).rsplit("::", 1)[-1]
        line, extracted = config_case(config_source, leaf)
        test_name = f"contract {row['id']} {row['upstream_name']}"
        expected = {"outcome": "success", **extracted}
        case = {
            "schema_version": 1,
            "case_id": row["id"],
            "upstream_name": row["upstream_name"],
            "owner_area": row["owner_area"],
            "test_name": test_name,
            "test_anchor": {"suite": CONFIG_SUITE, "test_name": test_name},
            "contract_case": f"MJ-CONTRACT::{row['id']}",
            "upstream_source": {
                "path": CONFIG_SOURCE,
                "line": line,
                "file_sha256": sha256(config_path),
            },
            "input": extracted["args"],
            "input_sha256": sha256_bytes(encoded(extracted["args"]).encode("utf-8")),
            "expected": expected,
            "expected_sha256": sha256_bytes(encoded(expected).encode("utf-8")),
        }
        rendered_config_cases.append(case)
        generated.append(case)
    write_or_check(repo / CONFIG_SUITE, render_config_tests(rendered_config_cases), check)

    invocation_path = upstream / INVOCATION_SOURCE
    invocation_source = invocation_path.read_text(encoding="utf-8")
    invocation_rows = [
        row
        for row in rows
        if row["owner_area"] == "execution-context"
        and row["scope"] == "compatibility"
        and str(row["upstream_name"]).startswith("invocation_parser::tests::")
        and str(row["upstream_name"]).rsplit("::", 1)[-1] in INVOCATION_CONTRACTS
    ]
    rendered_invocation_cases: list[dict[str, object]] = []
    for row in invocation_rows:
        leaf = str(row["upstream_name"]).rsplit("::", 1)[-1]
        definition = INVOCATION_CONTRACTS[leaf]
        match = re.search(rf"(?m)^\s*fn {re.escape(leaf)}\(\)", invocation_source)
        if match is None:
            raise ValueError(f"missing invocation source function {leaf}")
        line = invocation_source.count("\n", 0, match.start()) + 1
        test_name = f"contract {row['id']} {row['upstream_name']}"
        if "error_code" in definition:
            expected = {
                "outcome": "error",
                "code": definition["error_code"],
                "message": definition["error_message"],
            }
        else:
            expected = {
                "outcome": "success",
                "recipes": definition["recipes"],
                "values": definition["values"],
            }
        case = {
            "schema_version": 1,
            "case_id": row["id"],
            "upstream_name": row["upstream_name"],
            "owner_area": "execution-context",
            "test_name": test_name,
            "test_anchor": {"suite": INVOCATION_SUITE, "test_name": test_name},
            "contract_case": f"MJ-CONTRACT::{row['id']}",
            "upstream_source": {
                "path": INVOCATION_SOURCE,
                "line": line,
                "file_sha256": sha256(invocation_path),
            },
            "input": definition["args"],
            "input_sha256": sha256_bytes(encoded(definition["args"]).encode("utf-8")),
            "expected": expected,
            "expected_sha256": sha256_bytes(encoded(expected).encode("utf-8")),
            "source": definition["source"],
        }
        rendered_invocation_cases.append(case)
        generated.append(case)
    write_or_check(
        repo / INVOCATION_SUITE,
        render_invocation_tests(rendered_invocation_cases),
        check,
    )

    write_or_check(
        output,
        "".join(
            json.dumps(case, sort_keys=True, separators=(",", ":")) + "\n"
            for case in generated
            + [
                case
                for case in prior_cases
                if isinstance(case.get("test_anchor"), dict)
                and case["test_anchor"].get("suite")
                in {
                    "internal/semantic/remaining_contract_test.mbt",
                    "internal/executor/remaining_contract_test.mbt",
                    "internal/evaluator/remaining_contract_test.mbt",
                    "internal/cli/remaining_contract_test.mbt",
                    "internal/loader/remaining_contract_test.mbt",
                }
            ]
        ),
        check,
    )
    action = "verified" if check else "generated"
    print(f"{action} {len(generated)} independent parser/lexer/tangle contract cases")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", type=Path, default=root() / "_build/upstream/just-1.57.0/source")
    parser.add_argument("--output", type=Path, default=root() / "tests/upstream/just-1.57.0/contract-cases.jsonl")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    return generate(root(), args.upstream.resolve(), args.output.resolve(), args.check)


if __name__ == "__main__":
    raise SystemExit(main())
