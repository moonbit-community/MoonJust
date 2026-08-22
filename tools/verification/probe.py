#!/usr/bin/env python3
"""Run one platform probe with a bounded lifetime and inherited stdio."""

from __future__ import annotations

import argparse
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a probe command is required")
    print(f"platform probe: {args.label}", file=sys.stderr, flush=True)
    try:
        completed = subprocess.run(
            command,
            cwd=args.cwd,
            stdin=sys.stdin,
            stdout=sys.stdout,
            stderr=sys.stderr,
            check=False,
            timeout=args.timeout,
        )
    except subprocess.TimeoutExpired:
        print(
            f"platform probe timed out after {args.timeout:.0f}s: {args.label}",
            file=sys.stderr,
            flush=True,
        )
        return 124
    except OSError as error:
        print(f"platform probe could not start: {error}", file=sys.stderr, flush=True)
        return 127
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
