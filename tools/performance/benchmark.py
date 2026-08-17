#!/usr/bin/env python3
"""Interleaved official/native and fixed-budget wasm release benchmark."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import statistics
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


WASM_BUDGETS_MS = {
    "startup": (25.0, 35.0),
    "recipes-1000": (75.0, 120.0),
    "dag-1000": (150.0, 250.0),
}
MAX_WASM_RSS_KIB = 128 * 1024


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def process_tree_rss_kib(root_pid: int) -> int | None:
    if platform.system() != "Linux":
        return None
    parent: dict[int, int] = {}
    rss: dict[int, int] = {}
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            status = (entry / "status").read_text()
        except (OSError, UnicodeError):
            continue
        pid = int(entry.name)
        parent_match = next(
            (line for line in status.splitlines() if line.startswith("PPid:")), None
        )
        rss_match = next(
            (line for line in status.splitlines() if line.startswith("VmRSS:")), None
        )
        if parent_match:
            parent[pid] = int(parent_match.split()[1])
        if rss_match:
            rss[pid] = int(rss_match.split()[1])
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return sum(rss.get(pid, 0) for pid in descendants)


def run_sample(command: list[str], cwd: Path) -> dict[str, float | int | None]:
    started = time.perf_counter_ns()
    process = subprocess.Popen(
        command,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    peak: int | None = None
    stop = threading.Event()

    def sample() -> None:
        nonlocal peak
        while not stop.is_set():
            current = process_tree_rss_kib(process.pid)
            if current is not None:
                peak = max(peak or 0, current)
            stop.wait(0.001)

    sampler = threading.Thread(target=sample, daemon=True)
    sampler.start()
    try:
        _, stderr = process.communicate(timeout=120)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()
        raise RuntimeError(f"benchmark timed out: {command!r}")
    finally:
        stop.set()
        sampler.join(timeout=1)
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    if process.returncode != 0:
        raise RuntimeError(
            f"benchmark command failed ({process.returncode}): {command!r}\n"
            + stderr.decode(errors="replace")[:2000]
        )
    return {"elapsed_ms": elapsed_ms, "peak_rss_kib": peak}


def percentile95(values: list[float]) -> float:
    return sorted(values)[math.ceil(len(values) * 0.95) - 1]


def summarize(samples: list[dict[str, float | int | None]]) -> dict[str, object]:
    elapsed = [float(sample["elapsed_ms"]) for sample in samples]
    rss = [
        int(sample["peak_rss_kib"])
        for sample in samples
        if sample["peak_rss_kib"] is not None
    ]
    mean = statistics.fmean(elapsed)
    return {
        "median_ms": statistics.median(elapsed),
        "p95_ms": percentile95(elapsed),
        "cv": statistics.pstdev(elapsed) / mean if mean else 0.0,
        "peak_rss_kib": max(rss) if rss else None,
        "samples": samples,
    }


def write_fixtures(root: Path) -> dict[str, tuple[Path, list[str]]]:
    recipes10 = root / "recipes-10.just"
    recipes10.write_text("".join(f"r{index:04d}:\n" for index in range(10)))
    recipes1000 = root / "recipes-1000.just"
    recipes1000.write_text("".join(f"r{index:04d}:\n" for index in range(1000)))
    dag = root / "dag-1000.just"
    dag.write_text(
        "root: " + " ".join(f"node{index:04d}" for index in range(999)) + "\n"
        + "".join(f"node{index:04d}:\n" for index in range(999))
    )
    noops = root / "noops-100.just"
    noops.write_text(
        "all: " + " ".join(f"noop{index:03d}" for index in range(100)) + "\n"
        + "".join(f"noop{index:03d}:\n  @:\n" for index in range(100))
    )
    return {
        "startup": (recipes10, ["--version"]),
        "recipes-10": (recipes10, ["--summary"]),
        "recipes-1000": (recipes1000, ["--summary"]),
        "check": (recipes1000, ["--fmt", "--check"]),
        "format": (recipes1000, ["--fmt"]),
        "dag-1000": (dag, ["--dry-run", "root"]),
        "noops-100": (noops, ["all"]),
    }


def command_for(
    kind: str,
    binary: Path,
    fixture: Path,
    arguments: list[str],
    moonrun: str,
    policy: Path,
) -> list[str]:
    prefix = (
        [moonrun, "--policy", str(policy), str(binary)]
        if kind == "wasm"
        else [str(binary)]
    )
    if arguments == ["--version"]:
        return prefix + arguments
    return prefix + ["--justfile", str(fixture)] + arguments


def tool_output(command: list[str]) -> str:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return (result.stdout + result.stderr).strip()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--wasm", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--warmups", type=int, default=5)
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--report-only", action="store_true")
    args = parser.parse_args()
    args.official = args.official.resolve()
    args.native = args.native.resolve()
    args.wasm = args.wasm.resolve()
    args.policy = args.policy.resolve()
    args.output = args.output.resolve()
    if args.warmups < 0 or args.samples < 2:
        raise RuntimeError("benchmark requires non-negative warmups and at least 2 samples")
    moonrun = subprocess.run(
        ["sh", "-c", "command -v moonrun"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    for artifact in (args.official, args.native, args.wasm, args.policy):
        if not artifact.is_file():
            raise RuntimeError(f"benchmark input is missing: {artifact}")

    results: dict[str, dict[str, object]] = {}
    with tempfile.TemporaryDirectory(prefix="moonjust-benchmark-") as raw:
        root = Path(raw)
        fixtures = write_fixtures(root)
        for workload, (fixture, arguments) in fixtures.items():
            kinds = ("official", "native", "wasm")
            commands = {
                "official": command_for(
                    "official", args.official, fixture, arguments, moonrun, args.policy
                ),
                "native": command_for(
                    "native", args.native, fixture, arguments, moonrun, args.policy
                ),
                "wasm": command_for(
                    "wasm", args.wasm, fixture, arguments, moonrun, args.policy
                ),
            }
            for iteration in range(args.warmups):
                order = kinds if iteration % 2 == 0 else tuple(reversed(kinds))
                for kind in order:
                    run_sample(commands[kind], root)
            collected = {kind: [] for kind in kinds}
            for iteration in range(args.samples):
                order = kinds if iteration % 2 == 0 else tuple(reversed(kinds))
                for kind in order:
                    collected[kind].append(run_sample(commands[kind], root))
            results[workload] = {
                kind: summarize(collected[kind]) for kind in kinds
            }

    record = {
        "schema_version": 1,
        "commit": tool_output(["git", "rev-parse", "HEAD"]),
        "os": platform.platform(),
        "cpu": platform.processor() or platform.machine(),
        "python": platform.python_version(),
        "moon": tool_output(["moon", "version", "--all"]),
        "warmups": args.warmups,
        "sample_count": args.samples,
        "artifacts": {
            "official": {"path": str(args.official), "sha256": sha256(args.official)},
            "native": {"path": str(args.native), "sha256": sha256(args.native)},
            "wasm": {"path": str(args.wasm), "sha256": sha256(args.wasm)},
        },
        "workloads": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")

    failures: list[str] = []
    for workload, values in results.items():
        for kind in ("official", "native", "wasm"):
            summary = values[kind]
            if float(summary["cv"]) > 0.10:
                failures.append(
                    f"{workload}/{kind} CV {float(summary['cv']):.2%} exceeds 10%"
                )
        official = values["official"]
        native = values["native"]
        if float(native["median_ms"]) > float(official["median_ms"]) * 1.5:
            failures.append(f"{workload}/native median exceeds 1.5x official")
        if float(native["p95_ms"]) > float(official["p95_ms"]) * 1.75:
            failures.append(f"{workload}/native p95 exceeds 1.75x official")
        if (
            native["peak_rss_kib"] is not None
            and official["peak_rss_kib"] is not None
            and int(native["peak_rss_kib"]) > int(official["peak_rss_kib"]) * 2
        ):
            failures.append(f"{workload}/native peak RSS exceeds 2x official")
        if workload in WASM_BUDGETS_MS:
            median_budget, p95_budget = WASM_BUDGETS_MS[workload]
            wasm = values["wasm"]
            if float(wasm["median_ms"]) > median_budget:
                failures.append(
                    f"{workload}/wasm median {float(wasm['median_ms']):.2f}ms "
                    f"exceeds {median_budget:.0f}ms"
                )
            if float(wasm["p95_ms"]) > p95_budget:
                failures.append(
                    f"{workload}/wasm p95 {float(wasm['p95_ms']):.2f}ms "
                    f"exceeds {p95_budget:.0f}ms"
                )
            if (
                wasm["peak_rss_kib"] is not None
                and int(wasm["peak_rss_kib"]) > MAX_WASM_RSS_KIB
            ):
                failures.append(f"{workload}/wasm peak RSS exceeds 128 MiB")
    for failure in failures:
        print(f"performance gate: {failure}", file=sys.stderr)
    if failures and not args.report_only:
        return 1
    print(f"performance samples written to {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"performance gate error: {error}", file=sys.stderr)
        raise SystemExit(1)
