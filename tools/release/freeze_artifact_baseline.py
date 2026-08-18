#!/usr/bin/env python3
"""Audit repeat-build reports and fill missing frozen platform baselines."""

from __future__ import annotations

import argparse
import copy
import json
from collections import defaultdict
from pathlib import Path


EXPECTED_PLATFORMS = {"linux-x86_64", "macos-aarch64", "windows-x86_64"}


def load(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root is not an object: {path}")
    return value


def repeated_value(reports: list[dict[str, object]], section: str, key: str) -> object:
    values = {report[section][key] for report in reports}  # type: ignore[index]
    if len(values) != 1:
        raise ValueError(f"repeat builds differ for {section}.{key}: {sorted(values)!r}")
    return values.pop()


def repeated_json_value(
    reports: list[dict[str, object]], section: str, key: str
) -> object | None:
    values = [report.get(section, {}).get(key) for report in reports]  # type: ignore[union-attr]
    if any(value is None for value in values):
        return None
    encoded = {json.dumps(value, sort_keys=True) for value in values}
    if len(encoded) != 1:
        raise ValueError(f"repeat builds differ for {section}.{key}")
    return values[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--report", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    baseline = load(args.baseline)
    if baseline.get("schema_version") != 2:
        raise ValueError("artifact baseline must use schema 2")
    baseline_commit = baseline.get("commit")
    reports = [load(path) for path in args.report]
    by_platform: dict[str, list[dict[str, object]]] = defaultdict(list)
    for report in reports:
        if report.get("schema_version") != 2:
            raise ValueError("artifact report must use schema 2")
        if report.get("commit") != baseline_commit:
            raise ValueError(
                f"artifact report commit {report.get('commit')} differs from {baseline_commit}"
            )
        platform = report.get("platform")
        if platform not in EXPECTED_PLATFORMS:
            raise ValueError(f"unexpected release platform: {platform!r}")
        by_platform[str(platform)].append(report)
    missing_platforms = EXPECTED_PLATFORMS - set(by_platform)
    if missing_platforms:
        raise ValueError("missing repeated reports for: " + ", ".join(sorted(missing_platforms)))
    if any(len(values) < 2 for values in by_platform.values()):
        raise ValueError("every platform requires at least two clean build reports")

    proposed = copy.deepcopy(baseline)
    native = proposed.setdefault("native", {})
    assert isinstance(native, dict)
    for platform, platform_reports in sorted(by_platform.items()):
        executable = {
            "bytes": repeated_value(platform_reports, "native", "bytes"),
            "sha256": repeated_value(platform_reports, "native", "sha256"),
            "archive_bytes": repeated_value(platform_reports, "archive", "bytes"),
            "archive_sha256": repeated_value(platform_reports, "archive", "sha256"),
        }
        sections = repeated_json_value(platform_reports, "native", "sections")
        if sections is not None:
            executable["sections"] = sections
        existing = native.get(platform)
        if isinstance(existing, dict):
            for key in ("bytes", "sha256"):
                if key in existing and existing[key] != executable[key]:
                    raise ValueError(
                        f"refusing to overwrite frozen {platform}.{key}: "
                        f"{existing[key]!r} != {executable[key]!r}"
                    )
            executable = {**existing, **executable}
        native[platform] = executable

    all_reports = [report for values in by_platform.values() for report in values]
    wasm = {
        "bytes": repeated_value(all_reports, "wasm1", "bytes"),
        "sha256": repeated_value(all_reports, "wasm1", "sha256"),
    }
    sections = repeated_json_value(all_reports, "wasm1", "sections")
    if sections is not None:
        wasm["sections"] = sections
    existing_wasm = proposed.get("wasm1")
    if not isinstance(existing_wasm, dict):
        raise ValueError("frozen wasm1 baseline is missing")
    for key in ("bytes", "sha256"):
        if existing_wasm.get(key) != wasm[key]:
            raise ValueError(
                f"refusing to overwrite frozen wasm1.{key}: "
                f"{existing_wasm.get(key)!r} != {wasm[key]!r}"
            )

    encoded = json.dumps(proposed, indent=2, sort_keys=True) + "\n"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    if args.apply:
        if args.output.resolve() == args.baseline.resolve():
            raise ValueError("--output must be a separate audited proposal when using --apply")
        args.baseline.write_text(encoded, encoding="utf-8")
        print(f"applied audited artifact baseline to {args.baseline}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        raise SystemExit(f"artifact baseline audit error: {error}")
