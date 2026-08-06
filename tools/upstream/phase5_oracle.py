#!/usr/bin/env python3
"""Verify committed Phase 5 builtin outcomes against pinned just."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "tests/upstream/just-1.57.0/phase-5-oracle.jsonl"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", type=Path, required=True)
    args = parser.parse_args()
    rows = [json.loads(line) for line in CORPUS.read_text(encoding="utf-8").splitlines()]
    if len(rows) != 20:
        raise SystemExit(f"Phase 5 oracle expected 20 rows, found {len(rows)}")
    seen: set[str] = set()
    for row in rows:
        case_id = row["id"]
        if case_id in seen:
            raise SystemExit(f"duplicate Phase 5 oracle id {case_id}")
        seen.add(case_id)
        encoded = ", ".join(json.dumps(argument) for argument in row["arguments"])
        source = f'x := {row["builtin"]}({encoded})\n'
        result = subprocess.run(
            [str(args.upstream), "--justfile", "-", "--evaluate", "x"],
            input=source,
            text=True,
            capture_output=True,
            cwd=ROOT,
        )
        if "expected" in row:
            if result.returncode != 0 or result.stdout != row["expected"]:
                raise SystemExit(
                    f"{case_id} mismatch: exit={result.returncode} "
                    f"stdout={result.stdout!r} stderr={result.stderr!r}"
                )
        else:
            expected_error = row["expected_error"]
            if result.returncode == 0 or expected_error not in result.stderr:
                raise SystemExit(
                    f"{case_id} expected error {expected_error!r}: "
                    f"exit={result.returncode} stderr={result.stderr!r}"
                )
    print(f"Phase 5 Rust oracle verified: {len(rows)} cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
