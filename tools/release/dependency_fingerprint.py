#!/usr/bin/env python3
"""Resolve and normalize MoonBit direct dependency fingerprints."""

from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path


_IMPORT_LINE = re.compile(r'^\s*"(?P<module>[^"@]+)@(?P<version>[^"@]+)"\s*,?\s*$')


def direct_dependencies(moon_mod: Path) -> dict[str, str]:
    """Read the direct registry imports from a MoonBit ``moon.mod`` file."""
    lines = moon_mod.read_text(encoding="utf-8").splitlines()
    inside_imports = False
    dependencies: dict[str, str] = {}
    for line in lines:
        stripped = line.strip()
        if stripped == "import {":
            if inside_imports:
                raise ValueError(f"nested import block in {moon_mod}")
            inside_imports = True
            continue
        if inside_imports and stripped == "}":
            inside_imports = False
            continue
        if not inside_imports:
            continue
        match = _IMPORT_LINE.match(line)
        if match is None:
            raise ValueError(f"unsupported dependency declaration in {moon_mod}: {line!r}")
        module = match.group("module")
        version = match.group("version")
        if module in dependencies:
            raise ValueError(f"duplicate dependency {module!r} in {moon_mod}")
        dependencies[module] = version
    if inside_imports:
        raise ValueError(f"unterminated import block in {moon_mod}")
    if not dependencies:
        raise ValueError(f"no direct dependencies found in {moon_mod}")
    return dependencies


def _registry_index_path(module: str, moon_home: Path) -> Path:
    parts = module.split("/")
    if len(parts) != 2:
        raise ValueError(f"unsupported registry module name: {module}")
    return moon_home / "registry" / "index" / "user" / parts[0] / f"{parts[1]}.index"


def registry_checksum(module: str, version: str, moon_home: Path | None = None) -> str:
    home = moon_home or Path(os.environ.get("MOON_HOME", Path.home() / ".moon"))
    index = _registry_index_path(module, home)
    if not index.is_file():
        raise ValueError(f"registry index is missing: {index}")
    for raw in index.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        entry = json.loads(raw)
        if entry.get("name") == module and entry.get("version") == version:
            checksum = entry.get("checksum")
            if isinstance(checksum, str) and checksum:
                return checksum
            raise ValueError(f"registry checksum is missing for {module}@{version}")
    raise ValueError(f"registry entry is missing for {module}@{version}")


def latest_registry_record(
    module: str,
    moon_home: Path | None = None,
) -> dict[str, str]:
    """Return the newest published registry entry for a direct dependency."""
    home = moon_home or Path(os.environ.get("MOON_HOME", Path.home() / ".moon"))
    index = _registry_index_path(module, home)
    if not index.is_file():
        raise ValueError(f"registry index is missing: {index}")
    records: list[dict[str, str]] = []
    for raw in index.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        entry = json.loads(raw)
        if entry.get("name") != module:
            continue
        version = entry.get("version")
        checksum = entry.get("checksum")
        created_at = entry.get("created_at")
        if all(isinstance(value, str) and value for value in (version, checksum, created_at)):
            records.append(
                {
                    "module": module,
                    "version": version,
                    "checksum": checksum,
                    "created_at": created_at,
                }
            )
    if not records:
        raise ValueError(f"registry has no complete entries for {module}")
    latest = max(records, key=lambda record: record["created_at"])
    return {key: latest[key] for key in ("module", "version", "checksum")}


def dependency_records(
    moon_mod: Path,
    *,
    moon_home: Path | None = None,
) -> list[dict[str, str]]:
    dependencies = direct_dependencies(moon_mod)
    return [
        {
            "module": module,
            "version": version,
            "checksum": registry_checksum(module, version, moon_home),
        }
        for module, version in sorted(dependencies.items())
    ]


def latest_dependency_records(
    moon_mod: Path,
    *,
    moon_home: Path | None = None,
) -> list[dict[str, str]]:
    return [
        latest_registry_record(module, moon_home)
        for module in sorted(direct_dependencies(moon_mod))
    ]


def assert_declares_dependency_set(
    moon_mod: Path,
    expected: list[dict[str, str]],
) -> None:
    declared = direct_dependencies(moon_mod)
    expected_versions = {record["module"]: record["version"] for record in expected}
    if declared != expected_versions:
        raise ValueError(
            "candidate direct dependencies are not latest: "
            + json.dumps(
                {"declared": declared, "latest": expected_versions},
                sort_keys=True,
            )
        )


def dependency_fingerprint(records: list[dict[str, str]]) -> str:
    encoded = json.dumps(records, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def normalize_direct_dependencies(
    moon_mod: Path,
    target_records: list[dict[str, str]],
) -> None:
    """Replace only direct version literals in an extracted source tree."""
    text = moon_mod.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    targets = {record["module"]: record["version"] for record in target_records}
    seen: set[str] = set()
    inside_imports = False
    output: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped == "import {":
            inside_imports = True
            output.append(line)
            continue
        if inside_imports and stripped == "}":
            inside_imports = False
            output.append(line)
            continue
        if not inside_imports:
            output.append(line)
            continue
        match = _IMPORT_LINE.match(line.rstrip("\r\n"))
        if match is None:
            raise ValueError(f"unsupported dependency declaration in {moon_mod}: {line!r}")
        module = match.group("module")
        if module in targets:
            newline = "\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else ""
            output.append(f'  "{module}@{targets[module]}",' + newline)
            seen.add(module)
        else:
            output.append(line)
    missing = sorted(set(targets) - seen)
    if missing:
        raise ValueError(
            "merge-base direct dependency set differs; missing: " + ", ".join(missing)
        )
    if inside_imports:
        raise ValueError(f"unterminated import block in {moon_mod}")
    moon_mod.write_text("".join(output), encoding="utf-8")
