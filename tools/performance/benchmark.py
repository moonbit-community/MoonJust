#!/usr/bin/env python3
"""Reproducible end-to-end release benchmark with traceable evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = 4
LEGACY_SCHEMA_VERSION = 2
OFFICIAL_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
DEFAULT_SEED = 1_570
STABLE_CV = 0.05
STABLE_CI_HALF_WIDTH = 0.03
MIN_LATENCY_SAMPLES = 15
MAX_LATENCY_SAMPLES = 30
COLD_WARM_ROUNDS = 3
COLD_WARM_WARMUPS = 5


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def text_or_none(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return None


def cpuinfo_field(cpuinfo: str | None, name: str) -> str | None:
    if cpuinfo is None:
        return None
    for line in cpuinfo.splitlines():
        field, separator, value = line.partition(":")
        if separator and field.strip() == name:
            return value.strip()
    return None


def parse_cpu_list(value: str) -> set[int]:
    cpus: set[int] = set()
    for part in value.strip().split(","):
        if not part:
            continue
        left, separator, right = part.partition("-")
        if separator:
            cpus.update(range(int(left), int(right) + 1))
        else:
            cpus.add(int(left))
    return cpus


def machine_fingerprint() -> dict[str, object]:
    affinity = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else []
    load_1m = os.getloadavg()[0] if hasattr(os, "getloadavg") else None
    isolated_text = text_or_none(Path("/sys/devices/system/cpu/isolated")) or ""
    isolated = sorted(parse_cpu_list(isolated_text)) if isolated_text else []

    cpuinfo = text_or_none(Path("/proc/cpuinfo")) if platform.system() == "Linux" else None
    meminfo = text_or_none(Path("/proc/meminfo")) if platform.system() == "Linux" else None
    temperature_paths = sorted(Path("/sys/class/thermal").glob("thermal_zone*/temp"))
    temperatures = {
        str(path): value
        for path in temperature_paths
        if (value := text_or_none(path)) is not None
    }
    fingerprint: dict[str, object] = {
        "platform": platform.platform(),
        "system": platform.system(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "cpu": platform.processor() or platform.machine(),
        "cpu_model": cpuinfo_field(cpuinfo, "model name"),
        "microcode": cpuinfo_field(cpuinfo, "microcode"),
        "kernel": platform.release(),
        "memory_total": cpuinfo_field(meminfo, "MemTotal"),
        "affinity": affinity,
        "isolated_cpus": isolated,
        "load_1m": load_1m,
        "temperature_millidegrees": temperatures,
        "temperature_available": bool(temperature_paths),
        "cpuinfo_sha256": hashlib.sha256((cpuinfo or "").encode()).hexdigest(),
        "meminfo_sha256": hashlib.sha256((meminfo or "").encode()).hexdigest(),
    }
    return fingerprint


def benchmark_environment() -> dict[str, str]:
    """Expose the real runner platform to the shared portable Wasm host."""
    system = platform.system()
    os_name = {
        "Linux": "linux",
        "Darwin": "macos",
        "Windows": "windows",
    }.get(system, system.lower())
    machine = platform.machine()
    architecture = {
        "AMD64": "amd64",
        "x86_64": "x86_64",
        "arm64": "arm64",
        "aarch64": "aarch64",
    }.get(machine, machine)
    environment = os.environ.copy()
    environment["MOONJUST_OS"] = os_name
    environment["MOONJUST_ARCH"] = architecture
    return environment


def run_latency_sample(command: list[str], cwd: Path) -> float:
    started = time.perf_counter_ns()
    result = subprocess.run(
        command,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        env=benchmark_environment(),
        timeout=120,
    )
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000
    if result.returncode != 0:
        raise RuntimeError(
            f"benchmark command failed ({result.returncode}): {command!r}\n"
            + result.stderr.decode(errors="replace")[:2000]
        )
    return elapsed_ms


def memory_supported() -> bool:
    """Return whether this host exposes a trustworthy process RSS sampler."""
    return platform.system() == "Linux" and Path("/usr/bin/time").is_file()


def run_memory_sample(command: list[str], cwd: Path) -> int | None:
    if not memory_supported():
        return None
    with tempfile.NamedTemporaryFile(prefix="moonjust-rss-", delete=False) as stream:
        output = Path(stream.name)
    try:
        result = subprocess.run(
            ["/usr/bin/time", "-v", "-o", str(output), *command],
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            env=benchmark_environment(),
            timeout=120,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"benchmark command failed ({result.returncode}): {command!r}\n"
                + result.stderr.decode(errors="replace")[:2000]
            )
        for line in output.read_text(encoding="utf-8").splitlines():
            if "Maximum resident set size (kbytes):" in line:
                return int(line.rsplit(":", 1)[1].strip())
        raise RuntimeError("GNU time did not report maximum resident set size")
    finally:
        output.unlink(missing_ok=True)


def percentile95(values: list[float]) -> float:
    return sorted(values)[math.ceil(len(values) * 0.95) - 1]


def coefficient_of_variation(values: list[float]) -> float | None:
    if not values:
        return None
    mean = statistics.fmean(values)
    return statistics.pstdev(values) / mean if mean else 0.0


def median_ci_half_width(values: list[float]) -> float | None:
    """Approximate a relative 95% CI half-width for the sample median."""
    if len(values) < 2:
        return None
    median = statistics.median(values)
    if median == 0:
        return 0.0
    return 1.58 * statistics.pstdev(values) / math.sqrt(len(values)) / median


def stable_window(values: list[float], window: int = 5) -> bool:
    if len(values) < window:
        return False
    recent = values[-window:]
    cv = coefficient_of_variation(recent)
    ci = median_ci_half_width(recent)
    return cv is not None and ci is not None and cv <= STABLE_CV and ci <= STABLE_CI_HALF_WIDTH


def read_evidence(path: Path) -> dict[str, object]:
    """Read current evidence plus migration-era schema 2/3 artifacts."""
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("schema_version") not in {2, 3, SCHEMA_VERSION}:
        raise ValueError(f"unsupported performance evidence schema in {path}")
    if value.get("schema_version") != SCHEMA_VERSION:
        value = dict(value)
        value["legacy_schema_version"] = value["schema_version"]
        value["schema_version"] = SCHEMA_VERSION
    return value


def evidence_result_set(value: dict[str, object]) -> set[tuple[str, str, tuple[str, ...]]]:
    """Return the workload/command inventory used by shadow migration checks."""
    fixtures = value.get("fixtures", {})
    if not isinstance(fixtures, dict):
        return set()
    result: set[tuple[str, str, tuple[str, ...]]] = set()
    for workload, entry in fixtures.items():
        if not isinstance(entry, dict):
            continue
        commands = entry.get("commands", {})
        if not isinstance(commands, dict):
            continue
        for kind, value in commands.items():
            if isinstance(kind, str) and isinstance(value, list) and all(
                isinstance(part, str) for part in value
            ):
                normalized = tuple(
                    f"<fixture>/{Path(part).name}"
                    if "/moonjust-benchmark-" in part
                    else part
                    for part in value
                )
                result.add((str(workload), kind, normalized))
    return result


def shadow_result_sets_match(
    previous: dict[str, object], current: dict[str, object]
) -> bool:
    """Compare migration-era and current evidence inventories, not timings."""
    return evidence_result_set(previous) == evidence_result_set(current)


def summarize(elapsed: list[float], rss: list[int | None]) -> dict[str, object]:
    measured_rss = [value for value in rss if value is not None]
    return {
        "median_ms": statistics.median(elapsed),
        "p95_ms": percentile95(elapsed),
        "cv": coefficient_of_variation(elapsed),
        "rss_cv": coefficient_of_variation([float(value) for value in measured_rss]),
        "peak_rss_kib": max(measured_rss) if measured_rss else None,
        "latency_samples": len(elapsed),
        "memory_samples": len(rss),
        "memory_observations": len(measured_rss),
    }


def balanced_orders(kinds: Iterable[str], count: int, seed: int) -> list[tuple[str, ...]]:
    """Return deterministic cycles in which every kind occupies every position."""
    base = list(kinds)
    if not base:
        raise ValueError("benchmark schedule has no candidates")
    rng = random.Random(seed)
    rng.shuffle(base)
    result: list[tuple[str, ...]] = []
    for index in range(count):
        if index and index % len(base) == 0:
            rng.shuffle(base)
        offset = index % len(base)
        result.append(tuple(base[offset:] + base[:offset]))
    return result


def fixture_profile(workload: str) -> str:
    return "real-project" if workload.startswith("project-") else "synthetic-scale"


def fixture_files(workload: str, fixture: Path) -> list[Path]:
    """Return every file that contributes to a fixture, including modules."""
    files = [fixture]
    if workload == "project-modules":
        files.append(fixture.parent / "tools" / "mod.just")
    return files


def write_fixture(path: Path, contents: str) -> None:
    """Write platform-neutral UTF-8 bytes without Windows newline translation."""
    path.write_bytes(contents.encode("utf-8"))


def write_fixtures(root: Path) -> dict[str, tuple[Path, list[str]]]:
    recipes10 = root / "recipes-10.just"
    write_fixture(recipes10, "".join(f"r{index:04d}:\n" for index in range(10)))
    recipes100 = root / "recipes-100.just"
    write_fixture(recipes100, "".join(f"r{index:04d}:\n" for index in range(100)))
    recipes1000 = root / "recipes-1000.just"
    write_fixture(recipes1000, "".join(f"r{index:04d}:\n" for index in range(1000)))
    recipes5000 = root / "recipes-5000.just"
    write_fixture(recipes5000, "".join(f"r{index:04d}:\n" for index in range(5000)))
    dag = root / "dag-1000.just"
    write_fixture(
        dag,
        "root: " + " ".join(f"node{index:04d}" for index in range(999)) + "\n"
        + "".join(f"node{index:04d}:\n" for index in range(999))
    )
    noops = root / "noops-100.just"
    write_fixture(
        noops,
        "all: " + " ".join(f"noop{index:03d}" for index in range(100)) + "\n"
        + "".join(f"noop{index:03d}:\n  @:\n" for index in range(100))
    )
    project_modules = root / "project-modules.just"
    write_fixture(
        project_modules,
        "set shell := [\"sh\", \"-cu\"]\n"
        "project := \"moonjust\"\n"
        "mod tools\n\n"
        "[group(\"build\")]\n"
        "build: tools::prepare\n"
        "  @:\n"
    )
    tools = root / "tools"
    tools.mkdir()
    write_fixture(
        tools / "mod.just",
        "set shell := [\"sh\", \"-cu\"]\n"
        "prepare:\n"
        "  @:\n"
        "package:\n"
        "  @:\n"
    )
    project_parameters = root / "project-parameters.just"
    write_fixture(
        project_parameters,
        "set shell := [\"sh\", \"-cu\"]\n"
        "set positional-arguments\n"
        "project := \"moonjust\"\n"
        "alias b := build\n\n"
        "build target=\"debug\" *flags: (prepare target)\n"
        "  @:\n\n"
        "prepare target:\n"
        "  @:\n\n"
        "check:\n"
        "  @:\n\n"
        "all: build check\n"
        "  @:\n"
    )
    project_execution = root / "project-execution.just"
    write_fixture(
        project_execution,
        "set shell := [\"sh\", \"-cu\"]\n"
        "export BUILD_MODE := \"release\"\n\n"
        "all: lint test package\n"
        "  @:\n\n"
        "lint:\n"
        "  @:\n\n"
        "test:\n"
        "  @:\n\n"
        "package:\n"
        "  @:\n"
    )
    return {
        "startup": (recipes10, ["--version"]),
        "recipes-10": (recipes10, ["--summary"]),
        "recipes-100": (recipes100, ["--summary"]),
        "recipes-1000": (recipes1000, ["--summary"]),
        "recipes-5000": (recipes5000, ["--summary"]),
        "check": (recipes1000, ["--fmt", "--check"]),
        "format": (recipes1000, ["--fmt"]),
        "dag-1000": (dag, ["--dry-run", "root"]),
        "noops-100": (noops, ["all"]),
        "project-modules": (project_modules, ["--summary"]),
        "project-parameters": (project_parameters, ["--dry-run", "build", "release", "fast"]),
        "project-execution": (project_execution, ["all"]),
    }


def command_for(
    kind: str,
    binary: Path,
    fixture: Path,
    arguments: list[str],
    moonrun: str,
    policy: Path,
) -> list[str]:
    runtime = (
        [moonrun, "--policy", str(policy), str(binary)]
        if kind.endswith("wasm")
        else [str(binary)]
    )
    prefix = runtime
    if arguments == ["--version"]:
        return prefix + arguments
    return prefix + ["--justfile", str(fixture)] + arguments


def tool_output(command: list[str]) -> str:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return (result.stdout + result.stderr).strip()


def collect_phase_trace(command: list[str], cwd: Path) -> dict[str, object] | None:
    """Collect one opt-in MoonJust phase trace without affecting latency samples."""
    environment = benchmark_environment()
    environment["MOONJUST_PERF_TRACE"] = "1"
    result = subprocess.run(
        command,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        env=environment,
        timeout=120,
    )
    if result.returncode != 0:
        return {
            "error": f"trace command failed with exit code {result.returncode}",
            "stderr_tail": result.stderr.decode(errors="replace")[-2000:],
        }
    traces: list[dict[str, object]] = []
    detail_events: list[dict[str, object]] = []
    for line in result.stderr.decode(errors="replace").splitlines():
        if not line.startswith("MOONJUST_PERF_TRACE "):
            if line.startswith("MOONJUST_PERF_DETAIL "):
                value = json.loads(line.removeprefix("MOONJUST_PERF_DETAIL "))
                if isinstance(value, dict) and isinstance(value.get("events"), list):
                    detail_events.extend(value["events"])
            continue
        value = json.loads(line.removeprefix("MOONJUST_PERF_TRACE "))
        if isinstance(value, dict) and isinstance(value.get("events"), list):
            traces.append(value)
    if not traces and not detail_events:
        return None
    result_value = traces[-1] if traces else {"events": []}
    if detail_events:
        result_value = {**result_value, "detail_events": detail_events}
    return result_value


def baseline_metadata(path: Path | None) -> dict[str, object] | None:
    if path is None:
        return None
    metadata = path.parent / "metadata.json"
    if not metadata.is_file():
        return None
    try:
        value = json.loads(metadata.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def collect_phase(
    phase: str,
    workload: str,
    commands: dict[str, list[str]],
    cwd: Path,
    warmups: int,
    samples: int,
    seed: int,
    raw_rows: list[dict[str, object]],
    toolchain: str,
    artifact_hashes: dict[str, str],
) -> tuple[dict[str, list[float] | list[int | None]], float, bool]:
    started = time.perf_counter()
    kinds = tuple(commands)
    for order in balanced_orders(kinds, warmups, seed):
        for kind in order:
            if phase == "latency":
                run_latency_sample(commands[kind], cwd)
            else:
                run_memory_sample(commands[kind], cwd)
    collected: dict[str, list[float] | list[int | None]] = {kind: [] for kind in kinds}
    max_samples = min(samples, MAX_LATENCY_SAMPLES) if phase == "latency" else samples
    min_samples = MIN_LATENCY_SAMPLES if phase == "latency" else samples
    stable_windows = 0
    for iteration, order in enumerate(balanced_orders(kinds, max_samples, seed + 1)):
        for position, kind in enumerate(order):
            if phase == "latency":
                value: float | int | None = run_latency_sample(commands[kind], cwd)
                field = "elapsed_ms"
            else:
                value = run_memory_sample(commands[kind], cwd)
                field = "peak_rss_kib"
            collected[kind].append(value)  # type: ignore[arg-type]
            raw_rows.append(
                {
                    "schema_version": SCHEMA_VERSION,
                    "legacy_schema_version": LEGACY_SCHEMA_VERSION,
                    "phase": phase,
                    "workload": workload,
                    "iteration": iteration,
                    "position": position,
                    "kind": kind,
                    "command": commands[kind],
                    "target": kind.rsplit("-", 1)[-1] if "-" in kind else kind,
                    "exit_code": 0,
                    "toolchain": toolchain,
                    "artifact_sha256": artifact_hashes[kind],
                    "sampler": "gnu-time-max-rss" if phase == "memory" else "elapsed-process",
                    field: value,
                }
            )
        if phase == "latency" and iteration + 1 >= min_samples:
            if all(stable_window([float(value) for value in collected[kind]]) for kind in kinds):
                stable_windows += 1
            else:
                stable_windows = 0
            if stable_windows >= 3:
                break
    return collected, time.perf_counter() - started, phase == "latency" and len(next(iter(collected.values()))) < max_samples


def collect_cold_warm_phase(
    workload: str,
    commands: dict[str, list[str]],
    cwd: Path,
    seed: int,
    raw_rows: list[dict[str, object]],
    toolchain: str,
    artifact_hashes: dict[str, str],
) -> tuple[dict[str, dict[str, list[float]]], float]:
    """Measure fresh-process and warmed-process starts in balanced rounds.

    A cold observation is the first invocation of a new process in a round.
    A warm observation follows five invocations of that same command.  This
    intentionally does not drop the host page cache: doing so would require a
    privileged, global machine mutation and would not be a portable RC gate.
    """
    started = time.perf_counter()
    kinds = tuple(commands)
    collected = {
        kind: {"cold": [], "warm": []}
        for kind in kinds
    }
    for round_index in range(COLD_WARM_ROUNDS):
        order = balanced_orders(kinds, 1, seed + round_index)[0]
        for position, kind in enumerate(order):
            value = run_latency_sample(commands[kind], cwd)
            collected[kind]["cold"].append(value)
            raw_rows.append(
                {
                    "schema_version": SCHEMA_VERSION,
                    "legacy_schema_version": LEGACY_SCHEMA_VERSION,
                    "phase": "cold-warm",
                    "condition": "cold",
                    "round": round_index,
                    "workload": workload,
                    "iteration": round_index,
                    "position": position,
                    "kind": kind,
                    "command": commands[kind],
                    "target": kind.rsplit("-", 1)[-1] if "-" in kind else kind,
                    "exit_code": 0,
                    "toolchain": toolchain,
                    "artifact_sha256": artifact_hashes[kind],
                    "sampler": "elapsed-process",
                    "elapsed_ms": value,
                }
            )
            for _ in range(COLD_WARM_WARMUPS):
                run_latency_sample(commands[kind], cwd)
            value = run_latency_sample(commands[kind], cwd)
            collected[kind]["warm"].append(value)
            raw_rows.append(
                {
                    "schema_version": SCHEMA_VERSION,
                    "legacy_schema_version": LEGACY_SCHEMA_VERSION,
                    "phase": "cold-warm",
                    "condition": "warm",
                    "round": round_index,
                    "workload": workload,
                    "iteration": round_index,
                    "position": position,
                    "kind": kind,
                    "command": commands[kind],
                    "target": kind.rsplit("-", 1)[-1] if "-" in kind else kind,
                    "exit_code": 0,
                    "toolchain": toolchain,
                    "artifact_sha256": artifact_hashes[kind],
                    "sampler": "elapsed-process",
                    "elapsed_ms": value,
                }
            )
    return collected, time.perf_counter() - started


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--wasm", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--raw-output", type=Path)
    parser.add_argument("--warmups", type=int, default=5)
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--memory-warmups", type=int, default=2)
    parser.add_argument("--memory-samples", type=int, default=10)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--report-only", action="store_true")
    parser.add_argument(
        "--cold-warm",
        action="store_true",
        help="run three balanced cold-process/warmed-process rounds for real-project workloads",
    )
    parser.add_argument("--workload")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    for name in ("official", "native", "wasm", "policy", "output"):
        value = getattr(args, name)
        if value is not None:
            setattr(args, name, value.resolve())
    args.raw_output = (args.raw_output or args.output.with_suffix(".jsonl")).resolve()
    if args.warmups != 5 or args.memory_warmups != 2:
        raise RuntimeError("benchmark requires exactly 5 latency and 2 memory warmups")
    if args.samples < MIN_LATENCY_SAMPLES or args.samples > MAX_LATENCY_SAMPLES:
        raise RuntimeError("latency samples must be between 15 and 30")
    if args.memory_samples != 10:
        raise RuntimeError("memory samples must be exactly 10")
    moonrun = shutil.which("moonrun")
    if moonrun is None:
        raise RuntimeError("moonrun is not installed")
    artifacts = {
        "official": args.official,
        "candidate-native": args.native,
        "candidate-wasm": args.wasm,
    }
    for artifact in (*artifacts.values(), args.policy):
        if not artifact.is_file():
            raise RuntimeError(f"benchmark input is missing: {artifact}")

    machine = machine_fingerprint()
    environment_errors: list[str] = []
    official_commit = os.environ.get("MOONJUST_OFFICIAL_COMMIT", OFFICIAL_COMMIT)
    if official_commit != OFFICIAL_COMMIT:
        environment_errors.append(
            f"official benchmark commit must be {OFFICIAL_COMMIT}, observed {official_commit}"
        )
    candidate_commit = tool_output(["git", "rev-parse", "HEAD"])
    moon_toolchain = tool_output(["moon", "version", "--all"])
    args.raw_output.parent.mkdir(parents=True, exist_ok=True)
    results: dict[str, dict[str, object]] = {}
    fixtures_record: dict[str, dict[str, object]] = {}
    raw_rows: list[dict[str, object]] = []
    phase_durations: dict[str, float] = {"latency": 0.0, "memory": 0.0}
    early_stops: dict[str, bool] = {}
    cold_warm_results: dict[str, dict[str, dict[str, dict[str, object]]]] = {}
    cold_warm_duration = 0.0
    phase_traces: dict[str, dict[str, dict[str, object] | None]] = {}
    with tempfile.TemporaryDirectory(prefix="moonjust-benchmark-") as raw:
        root = Path(raw)
        fixtures = write_fixtures(root)
        selected_fixtures = fixtures
        if args.workload:
            if args.workload not in fixtures:
                raise RuntimeError(f"unknown benchmark workload: {args.workload}")
            selected_fixtures = {args.workload: fixtures[args.workload]}
        for workload, (fixture, arguments) in selected_fixtures.items():
            fixture_paths = fixture_files(workload, fixture)
            fixtures_record[workload] = {
                "profile": fixture_profile(workload),
                "sha256": sha256(fixture),
                "bytes": fixture.stat().st_size,
                "files": [
                    {
                        "path": str(path.relative_to(root)),
                        "bytes": path.stat().st_size,
                        "sha256": sha256(path),
                    }
                    for path in fixture_paths
                ],
                "arguments": arguments,
            }
            commands = {
                kind: command_for(kind, binary, fixture, arguments, moonrun, args.policy)
                for kind, binary in artifacts.items()
            }
            fixtures_record[workload]["commands"] = commands
            phase_traces[workload] = {}
            for kind in ("candidate-native", "candidate-wasm"):
                phase_traces[workload][kind] = collect_phase_trace(commands[kind], root)
            latency, latency_duration, latency_stopped = collect_phase(
                "latency", workload, commands, root, args.warmups, args.samples,
                args.seed + len(results) * 100, raw_rows, moon_toolchain,
                {kind: sha256(path) for kind, path in artifacts.items()},
            )
            if memory_supported():
                memory, memory_duration, _ = collect_phase(
                    "memory", workload, commands, root, args.memory_warmups,
                    args.memory_samples, args.seed + len(results) * 100 + 50,
                    raw_rows, moon_toolchain,
                    {kind: sha256(path) for kind, path in artifacts.items()},
                )
            else:
                memory = {kind: [] for kind in artifacts}
                memory_duration = 0.0
            phase_durations["latency"] += latency_duration
            phase_durations["memory"] += memory_duration
            early_stops[workload] = latency_stopped
            results[workload] = {
                kind: summarize(
                    [float(value) for value in latency[kind]],
                    [None if value is None else int(value) for value in memory[kind]],
                )
                for kind in artifacts
            }
            if args.cold_warm and (
                args.workload is not None or fixture_profile(workload) == "real-project"
            ):
                conditions, duration = collect_cold_warm_phase(
                    workload,
                    commands,
                    root,
                    args.seed + len(results) * 1000,
                    raw_rows,
                    moon_toolchain,
                    {kind: sha256(path) for kind, path in artifacts.items()},
                )
                cold_warm_duration += duration
                cold_warm_results[workload] = {
                    kind: {
                        condition: summarize(values, [])
                        for condition, values in conditions[kind].items()
                    }
                    for kind in artifacts
                }

    failures = list(environment_errors)
    required_kinds = {"official", "candidate-native", "candidate-wasm"}
    for workload, values in results.items():
        if set(values) != required_kinds:
            failures.append(f"{workload} is missing one or more benchmark artifacts")
        for kind, summary in values.items():
            if int(summary.get("latency_samples", 0)) < MIN_LATENCY_SAMPLES:
                failures.append(f"{workload}/{kind} has incomplete latency samples")
    if args.cold_warm:
        for workload, values in cold_warm_results.items():
            for kind, conditions in values.items():
                for condition in ("cold", "warm"):
                    if int(conditions[condition].get("latency_samples", 0)) != COLD_WARM_ROUNDS:
                        failures.append(f"{workload}/{kind}/{condition} has incomplete cold/warm samples")

    infrastructure_invalid = bool(environment_errors)
    args.raw_output.write_text(
        "".join(json.dumps(row, sort_keys=True) + "\n" for row in raw_rows),
        encoding="utf-8",
    )
    record = {
        "schema_version": SCHEMA_VERSION,
        "status": "infrastructure-invalid" if infrastructure_invalid else ("failed" if failures else "passed"),
        "commit": tool_output(["git", "rev-parse", "HEAD"]),
        "provenance": {
            "official_commit": official_commit,
            "official_commit_verified": official_commit == OFFICIAL_COMMIT,
            "candidate_commit": candidate_commit,
        },
        "machine": machine,
        "moon": moon_toolchain,
        "configuration": {
            "warmups": args.warmups,
            "samples": args.samples,
            "memory_warmups": args.memory_warmups,
            "memory_samples": args.memory_samples,
            "seed": args.seed,
            "latency_policy": {
                "warmups": 5,
                "min_samples": MIN_LATENCY_SAMPLES,
                "max_samples": MAX_LATENCY_SAMPLES,
                "stable_cv": STABLE_CV,
                "stable_ci_half_width": STABLE_CI_HALF_WIDTH,
                "stable_windows": 3,
            },
            "memory_policy": {
                "warmups": 2,
                "samples": 10,
                "supported": memory_supported(),
            },
            "portable_host": {
                "MOONJUST_OS": benchmark_environment()["MOONJUST_OS"],
                "MOONJUST_ARCH": benchmark_environment()["MOONJUST_ARCH"],
            },
        },
        "phases": {
            "durations_seconds": phase_durations,
            "latency_early_stops": early_stops,
            "cold_warm_duration_seconds": cold_warm_duration,
        },
        "cold_warm": {
            "enabled": args.cold_warm,
            "rounds": COLD_WARM_ROUNDS,
            "warmups_per_round": COLD_WARM_WARMUPS,
            "semantics": "per balanced round and artifact: cold=first fresh process, then five same-command warmups, then warm=fresh process",
            "workloads": cold_warm_results,
        },
        "phase_traces": phase_traces,
        "artifacts": {
            kind: {"path": str(path), "bytes": path.stat().st_size, "sha256": sha256(path)}
            for kind, path in artifacts.items()
        },
        "fixtures": fixtures_record,
        "raw_samples": {"path": str(args.raw_output), "sha256": sha256(args.raw_output)},
        "workloads": results,
        "failures": failures,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    for failure in failures:
        print(f"benchmark validation: {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"performance samples written to {args.output} and {args.raw_output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as error:
        print(f"benchmark error: {error}", file=sys.stderr)
        raise SystemExit(1)
