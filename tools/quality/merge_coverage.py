#!/usr/bin/env python3
"""Merge target coverage, filter production sources, and enforce thresholds."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path


PRODUCTION_PREFIXES = ("api/", "cmd/just/", "src/")
EXCLUDED_SUFFIXES = ("_test.mbt", "_wbtest.mbt", "pkg.generated.mbti")
REQUIRED_AREAS = {
    "lexer",
    "parser",
    "loader",
    "semantic",
    "executor",
    "runtime",
    "host_process",
}


def fail(message: str) -> None:
    raise ValueError(message)


def production_file(filename: str) -> bool:
    return filename.startswith(PRODUCTION_PREFIXES) and not filename.endswith(
        EXCLUDED_SUFFIXES
    )


def package_for(filename: str) -> str:
    if filename.startswith("src/"):
        return filename.split("/", 2)[1]
    if filename.startswith("cmd/just/"):
        return "cmd/just"
    return "api"


def read_coverage(paths: list[Path]) -> dict[str, dict[int, int]]:
    files: dict[str, dict[int, int]] = {}
    for path in paths:
        root = ET.parse(path).getroot()
        for source_class in root.findall(".//class"):
            filename = source_class.get("filename", "").replace(os.sep, "/")
            if not production_file(filename):
                continue
            lines = files.setdefault(filename, {})
            for line in source_class.findall("./lines/line"):
                number = int(line.get("number", "0"))
                hits = int(line.get("hits", "0"))
                lines[number] = max(lines.get(number, 0), hits)
    if not files:
        fail("coverage inputs contain no production MoonBit sources")
    return files


def rate(covered: int, valid: int) -> float:
    return covered / valid if valid else 1.0


def changed_lines(repo: Path, base: str | None) -> dict[str, set[int]]:
    command = ["git", "-C", str(repo), "diff", "--unified=0"]
    if base:
        command.extend([base, "HEAD"])
    else:
        command.append("HEAD")
    command.extend(["--", "api", "cmd/just", "src"])
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    current: str | None = None
    changed: dict[str, set[int]] = defaultdict(set)
    hunk = re.compile(r"^@@ -(?:\d+)(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
    for line in result.stdout.splitlines():
        if line.startswith("+++ b/"):
            current = line[6:]
            continue
        match = hunk.match(line)
        if current is None or match is None or not production_file(current):
            continue
        start = int(match.group(1))
        count = int(match.group(2) or "1")
        changed[current].update(range(start, start + count))
    return changed


def write_cobertura(
    output: Path, files: dict[str, dict[int, int]], package_counts: dict[str, list[int]]
) -> None:
    covered = sum(values[0] for values in package_counts.values())
    valid = sum(values[1] for values in package_counts.values())
    root = ET.Element(
        "coverage",
        {
            "lines-valid": str(valid),
            "lines-covered": str(covered),
            "line-rate": f"{rate(covered, valid):.6f}",
        },
    )
    sources = ET.SubElement(root, "sources")
    ET.SubElement(sources, "source").text = "."
    packages = ET.SubElement(root, "packages")
    for package in sorted(package_counts):
        package_covered, package_valid = package_counts[package]
        package_node = ET.SubElement(
            packages,
            "package",
            {
                "name": package,
                "line-rate": f"{rate(package_covered, package_valid):.6f}",
            },
        )
        classes = ET.SubElement(package_node, "classes")
        for filename in sorted(name for name in files if package_for(name) == package):
            lines = files[filename]
            file_covered = sum(hits > 0 for hits in lines.values())
            source_class = ET.SubElement(
                classes,
                "class",
                {
                    "name": filename,
                    "filename": filename,
                    "line-rate": f"{rate(file_covered, len(lines)):.6f}",
                },
            )
            line_nodes = ET.SubElement(source_class, "lines")
            for number, hits in sorted(lines.items()):
                ET.SubElement(
                    line_nodes,
                    "line",
                    {"number": str(number), "hits": str(hits)},
                )
    ET.indent(root, space="  ")
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--cobertura", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--base", default=os.environ.get("MOONJUST_COVERAGE_BASE"))
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args()

    repo = args.repo.resolve()
    files = read_coverage(args.inputs)
    package_counts: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for filename, lines in files.items():
        package = package_for(filename)
        package_counts[package][0] += sum(hits > 0 for hits in lines.values())
        package_counts[package][1] += len(lines)
    total_covered = sum(values[0] for values in package_counts.values())
    total_valid = sum(values[1] for values in package_counts.values())

    changed = changed_lines(repo, args.base)
    changed_valid = 0
    changed_covered = 0
    for filename, numbers in changed.items():
        instrumented = files.get(filename, {})
        for number in numbers:
            if number not in instrumented:
                continue
            changed_valid += 1
            changed_covered += instrumented[number] > 0

    package_rates = {
        package: rate(values[0], values[1])
        for package, values in sorted(package_counts.items())
    }
    summary = {
        "schema_version": 1,
        "overall": {
            "covered": total_covered,
            "valid": total_valid,
            "rate": rate(total_covered, total_valid),
        },
        "changed": {
            "covered": changed_covered,
            "valid": changed_valid,
            "rate": rate(changed_covered, changed_valid),
        },
        "packages": {
            package: {
                "covered": package_counts[package][0],
                "valid": package_counts[package][1],
                "rate": package_rates[package],
            }
            for package in sorted(package_counts)
        },
    }
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")
    write_cobertura(args.cobertura, files, package_counts)

    failures: list[str] = []
    if rate(total_covered, total_valid) < 0.80:
        failures.append(f"overall coverage {rate(total_covered, total_valid):.2%} < 80%")
    for area in sorted(REQUIRED_AREAS):
        area_rate = package_rates.get(area, 0.0)
        if area_rate < 0.85:
            failures.append(f"{area} coverage {area_rate:.2%} < 85%")
    if changed_valid and rate(changed_covered, changed_valid) < 0.90:
        failures.append(
            f"changed-line coverage {rate(changed_covered, changed_valid):.2%} < 90%"
        )
    if not args.baseline.is_file():
        failures.append(f"frozen package baseline is missing: {args.baseline}")
    else:
        baseline = json.loads(args.baseline.read_text())
        if baseline.get("schema_version") != 1:
            fail("unsupported package coverage baseline schema")
        for package, previous in baseline.get("packages", {}).items():
            current = package_rates.get(package)
            if current is None:
                failures.append(f"baseline package disappeared from coverage: {package}")
            elif current + 0.01 < previous:
                failures.append(
                    f"{package} coverage dropped from {previous:.2%} to {current:.2%}"
                )

    print(
        f"coverage overall={rate(total_covered, total_valid):.2%} "
        f"changed={rate(changed_covered, changed_valid):.2%} "
        f"({changed_covered}/{changed_valid})"
    )
    if failures:
        for failure in failures:
            print(f"coverage gate: {failure}", file=sys.stderr)
        if not args.report_only:
            return 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f"coverage gate error: {error}", file=sys.stderr)
        raise SystemExit(1)
