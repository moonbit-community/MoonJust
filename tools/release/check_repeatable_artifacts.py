#!/usr/bin/env python3
"""Compare clean repeat builds and emit machine-readable reproducibility evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_pair(value: str) -> tuple[str, Path, Path]:
    parts = value.split("=", 2)
    if len(parts) != 3 or not all(parts):
        raise ValueError(f"expected NAME=FIRST=SECOND, observed {value!r}")
    return parts[0], Path(parts[1]).resolve(), Path(parts[2]).resolve()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", required=True)
    parser.add_argument("--pair", action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    pairs: dict[str, dict[str, object]] = {}
    failures: list[str] = []
    for raw_pair in args.pair:
        name, first, second = parse_pair(raw_pair)
        if name in pairs:
            raise ValueError(f"duplicate repeatability pair: {name}")
        if not first.is_file() or not second.is_file():
            raise ValueError(f"repeatability input is missing for {name}")
        first_hash = sha256(first)
        second_hash = sha256(second)
        first_bytes = first.stat().st_size
        second_bytes = second.stat().st_size
        if first_hash != second_hash or first_bytes != second_bytes:
            failures.append(f"repeat builds differ for {name}")
        pairs[name] = {
            "bytes": second_bytes,
            "sha256": second_hash,
            "first": {"path": str(first), "bytes": first_bytes, "sha256": first_hash},
            "second": {"path": str(second), "bytes": second_bytes, "sha256": second_hash},
        }
    record = {
        "schema_version": 1,
        "status": "failed" if failures else "passed",
        "commit": subprocess.run(
            ["git", "rev-parse", "HEAD"], check=True, capture_output=True, text=True
        ).stdout.strip(),
        "platform": args.platform,
        "pairs": pairs,
        "failures": failures,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for failure in failures:
        print(f"repeatability gate: {failure}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"repeatability gate error: {error}", file=sys.stderr)
        raise SystemExit(2)
