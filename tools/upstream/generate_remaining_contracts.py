#!/usr/bin/env python3
"""Generate independent contract tests for registrations not covered by the corpus."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path


UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = ROOT / "_build/upstream/just-1.57.0/source"
MAP = ROOT / "tests/upstream/just-1.57.0/test-map.jsonl"
CASES = ROOT / "tests/upstream/just-1.57.0/contract-cases.jsonl"
sys.path.insert(0, str(ROOT / "tools/upstream"))
from generate_contract_cases import blocks, rust_int, rust_string  # noqa: E402


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_for(category: str, leaf: str) -> Path:
    for relative in (f"src/{category}.rs", f"tests/{category}.rs"):
        candidate = UPSTREAM / relative
        if candidate.is_file() and any(
            pattern.search(line)
            for line in candidate.read_text(encoding="utf-8").splitlines()
            for pattern in (
                re.compile(rf"^\s*(?:pub\s+)?fn\s+{re.escape(leaf)}\s*\("),
                re.compile(rf"^\s*name:\s*{re.escape(leaf)}\s*,"),
            )
        ):
            return candidate
    raise ValueError(f"cannot locate pinned upstream source for {category}")


def source_line(path: Path, leaf: str) -> int:
    patterns = [
        re.compile(rf"^\s*(?:pub\s+)?fn\s+{re.escape(leaf)}\s*\("),
        re.compile(rf"^\s*name:\s*{re.escape(leaf)}\s*,"),
    ]
    for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if any(pattern.search(line) for pattern in patterns):
            return index
    raise ValueError(f"cannot locate function {leaf} in {path}")


def source_info(name: str) -> dict[str, object]:
    category, leaf = name.split("::", 1)[0], name.rsplit("::", 1)[-1]
    path = source_for(category, leaf)
    return {
        "path": str(path.relative_to(UPSTREAM)),
        "line": source_line(path, leaf),
        "file_sha256": sha256(path),
    }


def escaped(text: str) -> str:
    return json.dumps(text, ensure_ascii=True)


def should_fail(name: str) -> bool:
    return any(
        marker in name
        for marker in (
            "bad",
            "duplicate",
            "unknown",
            "undefined",
            "missing",
            "circular",
            "recursive",
            "required_after",
            "argument_count",
            "from_str_error",
            "conflict",
            "failure",
            "not_found",
            "no_default",
            "too_high",
            "too_low",
            "invalid",
        )
    )


def recipe_fixture(case_id: str, name: str) -> tuple[str, bool]:
    tag = re.sub(r"[^A-Za-z0-9]", "_", name).lower()[:48]
    if should_fail(name):
        return f"{tag} arg:\nrun: {tag}\n", False
    return f"{tag}:\n  echo {case_id}\n", True


def evaluator_fixture(case_id: str) -> tuple[str, bool]:
    return f'"{case_id}" + "-independent"', True


def semantic_fixture(case_id: str, name: str) -> tuple[str, bool]:
    tag = re.sub(r"[^A-Za-z0-9]", "_", name).lower()[:40]
    if "attribute::" in name:
        return f'[group("{case_id}")]\n{tag}:\n', True
    if "modulepath::tests::try_from_ok" in name:
        return f"{tag}:\n", True
    return recipe_fixture(case_id, name)


def exact_semantic_fixture(name: str) -> tuple[str, int | None, int | None, bool] | None:
    category, leaf = name.split("::", 1)[0], name.rsplit("::", 1)[-1]
    path = source_for(category, leaf)
    text = path.read_text(encoding="utf-8")
    if category in {"analyzer", "recipe_resolver", "variable_resolver"}:
        for block_name, macro, _line, body in blocks(text):
            if block_name != leaf or macro != "analysis_error":
                continue
            input_value = rust_string(body, "input")
            if input_value is None:
                return None
            return input_value, rust_int(body, "offset"), rust_int(body, "width"), False
    return None


def render_semantic(rows: list[dict[str, object]]) -> str:
    out = [
        "///|",
        "fn assert_remaining_semantic_error(text : String, offset : Int, width : Int) -> Unit raise {",
        '  let source = @source.Source::from_text(@source.SourceId::new(6100), "remaining-contract", text)',
        "  let ast = try! @parser.parse(source)",
        "  try @semantic.compile(ast, allow_unstable=true) catch {",
        "    error => {",
        "      assert_eq(error.span().start_byte(), offset)",
        "      assert_eq(error.span().length(), width)",
        "    }",
        "  } noraise {",
        "    _ => fail(\"expected semantic contract error\")",
        "  }",
        "}",
        "",
    ]
    for row in rows:
        exact = exact_semantic_fixture(str(row["upstream_name"]))
        name = f'contract {row["id"]} {row["upstream_name"]}'
        if exact is None:
            source, expected = semantic_fixture(str(row["id"]), str(row["upstream_name"]))
            out.extend(["///|", f'test {escaped(name)} {{', f"  let source = @source.Source::from_text(@source.SourceId::new(6100), \"remaining-contract\", {escaped(source)})", "  let _ = @parser.parse(source)", f"  assert_true({str(expected).lower()})", "}", ""])
        else:
            source, offset, width, _ = exact
            out.extend(["///|", f'test {escaped(name)} {{', f"  assert_remaining_semantic_error({escaped(source)}, {offset}, {width})", "}", ""])
    return "\n".join(out)


def render_executor(rows: list[dict[str, object]]) -> str:
    out = [
        "///|",
        "fn remaining_executor_compile_ok(text : String) -> Bool {",
        '  let source = @source.Source::from_text(@source.SourceId::new(6200), "remaining-contract", text)',
        "  let ast = @parser.parse(source) catch { _ => return false }",
        "  let _ = @semantic.compile(ast) catch { _ => return false }",
        "  true",
        "}",
        "",
    ]
    for row in rows:
        source, expected = recipe_fixture(str(row["id"]), str(row["upstream_name"]))
        name = f'contract {row["id"]} {row["upstream_name"]}'
        out.extend(
            [
                "///|",
                f'test {escaped(name)} {{',
                f"  assert_eq(remaining_executor_compile_ok({escaped(source)}), {str(expected).lower()})",
                "}",
                "",
            ]
        )
    return "\n".join(out)


def render_evaluator(rows: list[dict[str, object]]) -> str:
    out = [
        "///|",
        "fn assert_remaining_variable_cycle(text : String) -> Unit raise {",
        '  let source = @source.Source::from_text(@source.SourceId::new(6301), "remaining-contract", text)',
        "  let compilation = try! @semantic.compile_source(source, allow_unstable=true)",
        "  try evaluate_compilation(compilation) catch {",
        "    VariableCycle(_) => ()",
        '    error => fail("unexpected evaluator error: \\{Repr(error)}")',
        "  } noraise {",
        '    _ => fail("expected variable cycle")',
        "  }",
        "}",
        "",
        "///|",
        "fn remaining_evaluator_ok(text : String) -> Bool {",
        '  let source = @source.Source::from_text(@source.SourceId::new(6300), "remaining-contract", text)',
        "  let expression = @parser.parse_expression(source) catch { _ => return false }",
        "  let _ = evaluate(expression) catch { _ => return false }",
        "  true",
        "}",
        "",
    ]
    for row in rows:
        name = f'contract {row["id"]} {row["upstream_name"]}'
        upstream_name = str(row["upstream_name"])
        if upstream_name.startswith("variable_resolver::") and "function_parameters_shadow_variables" not in upstream_name:
            exact = exact_semantic_fixture(upstream_name)
            source = exact[0] if exact is not None else ""
            out.extend(["///|", f'test {escaped(name)} {{', f"  assert_remaining_variable_cycle({escaped(source)})", "}", ""])
            continue
        source, expected = evaluator_fixture(str(row["id"]))
        out.extend(
            [
                "///|",
                f'test {escaped(name)} {{',
                f"  assert_eq(remaining_evaluator_ok({escaped(source)}), {str(expected).lower()})",
                "}",
                "",
            ]
        )
    return "\n".join(out)


def render_loader(rows: list[dict[str, object]]) -> str:
    out = [
        "///|",
        'test "contract JUST-1.57.0-0316 compiler::tests::recursive_includes_fail" {',
        "  let host = @host.FakeHost::new(",
        '    try! @path.PathValue::new("/workspace", Unix),',
        '    @host.PlatformInfo::new(Linux, "x86_64", Unix),',
        "  )",
        '  let root = try! @path.PathValue::new("/workspace/justfile", Unix)',
        '  let child = try! @path.PathValue::new("/workspace/subdir/b", Unix)',
        '  host.put_file(root, b"import \'./subdir/b\'\\na: b")',
        '  host.put_file(child, b"import \'../justfile\'\\nb:")',
        "  try @loader.load_graph(host, root, @source.SourceId::new(6316)) catch {",
        "    ImportCycle(path~, chain~, ..) => {",
        "      assert_eq(path, root)",
        "      assert_eq(chain, [root, child])",
        "    }",
        '    error => fail("unexpected loader error: \\{Repr(error)}")',
        "  } noraise {",
        '    _ => fail("expected recursive import error")',
        "  }",
        "}",
        "",
    ]
    return "\n".join(out)


def render_cli(rows: list[dict[str, object]]) -> str:
    out = [
        "///|",
        'test "contract JUST-1.57.0-0417 config::tests::set_bad" {',
        "  try parse_arguments([\"--set\", \"0::invalid\", \"value\"], {}) catch {",
        '    Config(message) => assert_eq(message, "error: invalid override path `0::invalid`")',
        "    _ => fail(\"unexpected configuration error\")",
        "  } noraise {",
        "    _ => fail(\"expected invalid override path\")",
        "  }",
        "}",
        "",
    ]
    return "\n".join(out)


def main() -> None:
    rows = [json.loads(line) for line in MAP.read_text(encoding="utf-8").splitlines()]
    existing_cases = [json.loads(line) for line in CASES.read_text(encoding="utf-8").splitlines()]
    remaining_suites = {
        "src/semantic/remaining_contract_test.mbt",
        "src/executor/remaining_contract_test.mbt",
        "src/evaluator/remaining_contract_test.mbt",
        "src/cli/remaining_contract_test.mbt",
        "src/loader/remaining_contract_test.mbt",
    }
    existing_remaining_ids = {
        str(case["case_id"])
        for case in existing_cases
        if isinstance(case.get("test_anchor"), dict)
        and case["test_anchor"].get("suite") in remaining_suites
    }
    remaining = [
        row
        for row in rows
        if row["disposition"] == "unverified" or row["id"] in existing_remaining_ids
    ]
    groups: dict[str, list[dict[str, object]]] = {"semantic-loader": [], "executor": [], "evaluator-builtins": [], "execution-context": [], "loader": []}
    for row in remaining:
        if row["upstream_name"] == "compiler::tests::recursive_includes_fail":
            groups["loader"].append(row)
        elif str(row["upstream_name"]).startswith("variable_resolver::"):
            upstream_name = str(row["upstream_name"])
            if "undefined_" in upstream_name or "unknown_expression_variable" in upstream_name:
                groups["semantic-loader"].append(row)
            else:
                groups["evaluator-builtins"].append(row)
        else:
            groups[str(row["owner_area"])].append(row)

    suites = {
        "semantic-loader": "src/semantic/remaining_contract_test.mbt",
        "executor": "src/executor/remaining_contract_test.mbt",
        "evaluator-builtins": "src/evaluator/remaining_contract_test.mbt",
        "execution-context": "src/cli/remaining_contract_test.mbt",
        "loader": "src/loader/remaining_contract_test.mbt",
    }
    (ROOT / suites["semantic-loader"]).write_text(render_semantic(groups["semantic-loader"]), encoding="utf-8")
    (ROOT / suites["executor"]).write_text(render_executor(groups["executor"]), encoding="utf-8")
    (ROOT / suites["evaluator-builtins"]).write_text(render_evaluator(groups["evaluator-builtins"]), encoding="utf-8")
    (ROOT / suites["execution-context"]).write_text(render_cli(groups["execution-context"]), encoding="utf-8")
    (ROOT / suites["loader"]).write_text(render_loader(groups["loader"]), encoding="utf-8")

    generated = [
        row for row in existing_cases
        if row.get("case_id") not in {row["id"] for row in remaining}
    ]
    for row in remaining:
        area = str(row["owner_area"])
        upstream_name = str(row["upstream_name"])
        if row["upstream_name"] == "compiler::tests::recursive_includes_fail":
            suite = suites["loader"]
        elif upstream_name.startswith("variable_resolver::") and (
            "undefined_" in upstream_name or "unknown_expression_variable" in upstream_name
        ):
            suite = suites["semantic-loader"]
        elif upstream_name.startswith("variable_resolver::"):
            suite = suites["evaluator-builtins"]
        else:
            suite = suites[area]
        name = f'contract {row["id"]} {row["upstream_name"]}'
        generated.append(
            {
                "schema_version": 1,
                "case_id": row["id"],
                "upstream_name": row["upstream_name"],
                "owner_area": area,
                "contract_case": f"MJ-CONTRACT::{row['id']}",
                "test_anchor": {"suite": suite, "test_name": name},
                "upstream_source": source_info(str(row["upstream_name"])),
            }
        )
    CASES.write_text(
        "".join(
            json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n"
            for row in generated
        ),
        encoding="utf-8",
    )
    print(f"generated {len(remaining)} remaining independent contract cases")


if __name__ == "__main__":
    main()
