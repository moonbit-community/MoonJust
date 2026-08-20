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
    for macro in ("test", "error"):
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
    write_or_check(
        output,
        "".join(
            json.dumps(case, sort_keys=True, separators=(",", ":")) + "\n"
            for case in generated
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
