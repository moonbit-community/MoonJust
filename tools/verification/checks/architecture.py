#!/usr/bin/env python3
"""Check the package ownership boundaries used by the CI quality tier."""

from __future__ import annotations

import re
import sys
from pathlib import Path


CORE_PACKAGES = (
    "source", "diagnostic", "path", "host", "cli", "lexer", "syntax", "parser",
    "formatter", "semantic", "loader", "value", "builtin", "evaluator", "environment",
    "invocation", "workdir", "scheduler", "cache", "executor", "application",
)
ASYNC_PACKAGES = {"loader", "evaluator", "executor", "application"}
TARGET_SPECIALIZED = {"loader", "application"}


def fail(message: str) -> None:
    raise SystemExit(f"architecture boundary error: {message}")


def production_files(directory: Path) -> list[Path]:
    return sorted(
        path
        for path in directory.glob("*.mbt")
        if not path.name.endswith(("_test.mbt", "_wbtest.mbt"))
    )


def main() -> int:
    repo = Path(__file__).resolve().parents[3]
    for entry in (repo / "tools").iterdir():
        if entry.is_file() and entry.name not in {"README.md", "runner.py"}:
            fail(f"unexpected file at tools root: {entry.name}")
    for directory in ("differential", "oracles", "probes", "quality", "release", "spikes", "upstream", "verification"):
        if not (repo / "tools" / directory).is_dir():
            fail(f"missing tools/{directory} directory")
    checks = {"#cfg", "#external", "native-stub"}
    for package in CORE_PACKAGES:
        package_dir = repo / "src" / package
        if not (package_dir / "moon.pkg").is_file() or not (package_dir / "pkg.generated.mbti").is_file():
            fail(f"missing generated interface for src/{package}")
        for path in production_files(package_dir):
            text = path.read_text(encoding="utf-8")
            if package not in TARGET_SPECIALIZED and any(token in text for token in checks):
                fail(f"target-specific implementation found in {path}")
            if package not in ASYNC_PACKAGES and package != "host" and re.search(r"\basync\s+fn\b", text):
                fail(f"async implementation found in {path}")
    for path in (repo / "api").glob("*.mbti"):
        if "ZSeanYves/MoonJust/src/" in path.read_text(encoding="utf-8"):
            fail("stable API interface leaks an src package type")
    print(f"architecture boundaries verified for {len(CORE_PACKAGES)} core packages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
