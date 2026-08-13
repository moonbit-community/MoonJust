#!/usr/bin/env python3
import argparse
import json
import pathlib
import re
import shutil


def fail(message: str) -> None:
    raise SystemExit(f"Phase 11 dependency copy error: {message}")


def declared_dependencies(manifest: pathlib.Path) -> list[tuple[str, str]]:
    text = manifest.read_text()
    block = re.search(r"^import \{\n(.*?)^\}", text, re.M | re.S)
    if block is None:
        fail("moon.mod import block is missing")
    dependencies = re.findall(
        r'^\s*"([^"@]+)@([^"@]+)",\s*$', block.group(1), re.M
    )
    lines = [line for line in block.group(1).splitlines() if line.strip()]
    if len(dependencies) != len(lines) or len(dependencies) != len(set(dependencies)):
        fail("dependencies must be unique exact name@version entries")
    return dependencies


def source_version(module: pathlib.Path) -> str:
    current = module / "moon.mod"
    legacy = module / "moon.mod.json"
    if current.is_file():
        versions = re.findall(r'^version = "([^"]+)"$', current.read_text(), re.M)
        if len(versions) == 1:
            return versions[0]
    elif legacy.is_file():
        value = json.loads(legacy.read_text()).get("version")
        if isinstance(value, str):
            return value
    fail(f"dependency version metadata is missing: {module}")


def ignore(directory: str, names: list[str]) -> set[str]:
    del directory
    return {
        name
        for name in names
        if name in {".git", "_build"} or name.endswith(" 2") or name.endswith(".profraw")
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--target", type=pathlib.Path, required=True)
    args = parser.parse_args()

    copied = []
    for name, version in declared_dependencies(args.manifest):
        source = args.source / name
        target = args.target / name
        if not source.is_dir():
            fail(f"resolved source is missing for {name}@{version}")
        if source_version(source) != version:
            fail(f"resolved source version differs for {name}@{version}")
        if target.exists():
            fail(f"target already exists for {name}@{version}")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, target, symlinks=False, ignore=ignore)
        copied.append(f"{name}@{version}")
    print(f"Copied {len(copied)} exact dependency sources: {', '.join(copied)}")


if __name__ == "__main__":
    main()
