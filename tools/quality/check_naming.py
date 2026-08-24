#!/usr/bin/env python3
"""Check the repository's source naming conventions without third-party tools."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


SOURCE_NAME = re.compile(r"^[a-z0-9][a-z0-9_]*\.(?:mbt|c)$")
FUNCTION_NAME = re.compile(r"^\s*(?:pub\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)?)")
CONSTANT_NAME = re.compile(r"^\s*(?:pub\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\b")
SNAKE_CASE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$")
UPPER_SNAKE_CASE = re.compile(r"^[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*$")


def source_files(root: Path) -> list[Path]:
    paths: list[Path] = []
    for directory in (root / "src", root / "api", root / "cmd" / "just"):
        if directory.is_dir():
            paths.extend(path for path in directory.rglob("*") if path.is_file())
    return sorted(paths)


def check(root: Path) -> list[str]:
    errors: list[str] = []
    for path in source_files(root):
        relative = path.relative_to(root).as_posix()
        if path.suffix in {".mbt", ".c"} and not SOURCE_NAME.fullmatch(path.name):
            errors.append(f"{relative}: file name must be lower_snake_case")
        if path.suffix != ".mbt" or path.name.endswith(".mbti"):
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError as error:
            errors.append(f"{relative}: cannot decode as UTF-8: {error}")
            continue
        for line_number, line in enumerate(lines, 1):
            function = FUNCTION_NAME.match(line)
            if function:
                name = function.group(1).split("::")[-1]
                if not SNAKE_CASE.fullmatch(name):
                    errors.append(f"{relative}:{line_number}: function '{name}' must be lower_snake_case")
            constant = CONSTANT_NAME.match(line)
            if constant and not UPPER_SNAKE_CASE.fullmatch(constant.group(1)):
                errors.append(
                    f"{relative}:{line_number}: constant '{constant.group(1)}' must be UPPER_SNAKE_CASE"
                )
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args(argv)
    errors = check(args.root.resolve())
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("naming check: passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
