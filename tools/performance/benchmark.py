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


SCHEMA_VERSION = 3
LEGACY_SCHEMA_VERSION = 2
OFFICIAL_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
DEFAULT_SEED = 1_570
MAX_CV = 0.10
STABLE_CV = 0.05
STABLE_CI_HALF_WIDTH = 0.03
MIN_LATENCY_SAMPLES = 15
MAX_LATENCY_SAMPLES = 30
MAX_CANDIDATE_REGRESSION = 1.02
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


def text_or_none(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return None


def linux_cpu_value(cpu: int, name: str) -> str | None:
    return text_or_none(Path(f"/sys/devices/system/cpu/cpu{cpu}/cpufreq/{name}"))


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


def runnable_processes_on_cpu(cpu: int) -> list[dict[str, object]]:
    """Return unrelated runnable tasks most recently scheduled on one CPU."""
    if platform.system() != "Linux":
        return []
    own_ancestry = {os.getpid(), os.getppid()}
    rows: list[dict[str, object]] = []
    proc = Path("/proc")
    for process_dir in proc.iterdir():
        if not process_dir.name.isdigit():
            continue
        for task_dir in (process_dir / "task").glob("[0-9]*"):
            try:
                stat = (task_dir / "stat").read_text(encoding="utf-8")
                close = stat.rfind(")")
                fields = stat[close + 2 :].split()
                state = fields[0]
                processor = int(fields[36])
                pid = int(process_dir.name)
                if processor == cpu and state == "R" and pid not in own_ancestry:
                    rows.append(
                        {
                            "pid": pid,
                            "task": int(task_dir.name),
                            "command": stat[stat.find("(") + 1 : close],
                        }
                    )
            except (OSError, UnicodeError, ValueError, IndexError):
                continue
    return rows


def machine_fingerprint(authoritative: bool) -> tuple[dict[str, object], list[str]]:
    errors: list[str] = []
    cpu_text = os.environ.get("MOONJUST_PERF_CPU")
    selected_cpu: int | None = None
    if cpu_text:
        try:
            selected_cpu = int(cpu_text)
            if selected_cpu < 0:
                raise ValueError
        except ValueError:
            errors.append("MOONJUST_PERF_CPU must be a non-negative integer")
    elif authoritative:
        errors.append("MOONJUST_PERF_CPU is required for an authoritative run")

    affinity = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else []
    governor = (
        linux_cpu_value(selected_cpu, "scaling_governor")
        if selected_cpu is not None and platform.system() == "Linux"
        else None
    )
    load_1m = os.getloadavg()[0] if hasattr(os, "getloadavg") else None
    isolated_text = text_or_none(Path("/sys/devices/system/cpu/isolated")) or ""
    isolated = sorted(parse_cpu_list(isolated_text)) if isolated_text else []
    runnable = runnable_processes_on_cpu(selected_cpu) if selected_cpu is not None else []
    if authoritative:
        if platform.system() != "Linux" or platform.machine() not in {"x86_64", "AMD64"}:
            errors.append("authoritative performance runs require Linux x86_64")
        if shutil.which("taskset") is None:
            errors.append("taskset is required for an authoritative run")
        if selected_cpu is not None and affinity and selected_cpu not in affinity:
            errors.append(f"CPU {selected_cpu} is outside the runner affinity")
        if governor != "performance":
            errors.append(f"CPU governor must be performance, observed {governor!r}")
        if load_1m is None or load_1m > 0.5:
            errors.append(f"1-minute load average must be <= 0.5, observed {load_1m!r}")
        if runnable:
            errors.append(f"CPU {selected_cpu} has unrelated runnable tasks: {runnable!r}")

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
        "selected_cpu": selected_cpu,
        "affinity": affinity,
        "isolated_cpus": isolated,
        "governor": governor,
        "scaling_current_khz": (
            linux_cpu_value(selected_cpu, "scaling_cur_freq")
            if selected_cpu is not None and platform.system() == "Linux"
            else None
        ),
        "scaling_min_khz": (
            linux_cpu_value(selected_cpu, "scaling_min_freq")
            if selected_cpu is not None and platform.system() == "Linux"
            else None
        ),
        "scaling_max_khz": (
            linux_cpu_value(selected_cpu, "scaling_max_freq")
            if selected_cpu is not None and platform.system() == "Linux"
            else None
        ),
        "scaling_driver": (
            linux_cpu_value(selected_cpu, "scaling_driver")
            if selected_cpu is not None and platform.system() == "Linux"
            else None
        ),
        "load_1m": load_1m,
        "temperature_millidegrees": temperatures,
        "temperature_available": bool(temperature_paths),
        "cpuinfo_sha256": hashlib.sha256((cpuinfo or "").encode()).hexdigest(),
        "meminfo_sha256": hashlib.sha256((meminfo or "").encode()).hexdigest(),
        "runnable_tasks_on_selected_cpu": runnable,
    }
    return fingerprint, errors


def command_prefix(cpu: int | None) -> list[str]:
    if cpu is not None and platform.system() == "Linux":
        return ["taskset", "-c", str(cpu)]
    return []


def run_latency_sample(command: list[str], cwd: Path) -> float:
    started = time.perf_counter_ns()
    result = subprocess.run(
        command,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
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
    """Read both migration-era schema 2 and current schema 3 evidence."""
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict) or value.get("schema_version") not in {
        LEGACY_SCHEMA_VERSION,
        SCHEMA_VERSION,
    }:
        raise ValueError(f"unsupported performance evidence schema in {path}")
    if value.get("schema_version") == LEGACY_SCHEMA_VERSION:
        value = dict(value)
        value["legacy_schema_version"] = LEGACY_SCHEMA_VERSION
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
    cpu: int | None,
) -> list[str]:
    runtime = (
        [moonrun, "--policy", str(policy), str(binary)]
        if kind.endswith("wasm")
        else [str(binary)]
    )
    prefix = command_prefix(cpu) + runtime
    if arguments == ["--version"]:
        return prefix + arguments
    return prefix + ["--justfile", str(fixture)] + arguments


def tool_output(command: list[str]) -> str:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return (result.stdout + result.stderr).strip()


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


def add_ratio_failure(
    failures: list[str], workload: str, candidate: dict[str, object], baseline: dict[str, object]
) -> None:
    if float(candidate["median_ms"]) > float(baseline["median_ms"]) * MAX_CANDIDATE_REGRESSION:
        failures.append(f"{workload}/candidate median regressed by more than 2% from merge-base")
    if float(candidate["p95_ms"]) > float(baseline["p95_ms"]) * MAX_CANDIDATE_REGRESSION:
        failures.append(f"{workload}/candidate p95 regressed by more than 2% from merge-base")
    candidate_rss = candidate["peak_rss_kib"]
    baseline_rss = baseline["peak_rss_kib"]
    if candidate_rss is not None and baseline_rss is not None and int(candidate_rss) > int(baseline_rss) * MAX_CANDIDATE_REGRESSION:
        failures.append(f"{workload}/candidate peak RSS regressed by more than 2% from merge-base")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--official", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--wasm", type=Path, required=True)
    parser.add_argument("--baseline-native", type=Path)
    parser.add_argument("--baseline-wasm", type=Path)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--raw-output", type=Path)
    parser.add_argument("--warmups", type=int, default=5)
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--memory-warmups", type=int, default=2)
    parser.add_argument("--memory-samples", type=int, default=10)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    parser.add_argument("--authoritative", action="store_true")
    parser.add_argument("--report-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    for name in ("official", "native", "wasm", "baseline_native", "baseline_wasm", "policy", "output"):
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
    if (args.baseline_native is None) != (args.baseline_wasm is None):
        raise RuntimeError("merge-base native and wasm artifacts must be supplied together")
    moonrun = shutil.which("moonrun")
    if moonrun is None:
        raise RuntimeError("moonrun is not installed")
    artifacts = {
        "official": args.official,
        "candidate-native": args.native,
        "candidate-wasm": args.wasm,
    }
    if args.baseline_native is not None:
        artifacts["baseline-native"] = args.baseline_native
        artifacts["baseline-wasm"] = args.baseline_wasm
    for artifact in (*artifacts.values(), args.policy):
        if not artifact.is_file():
            raise RuntimeError(f"benchmark input is missing: {artifact}")

    machine, environment_errors = machine_fingerprint(args.authoritative)
    official_commit = os.environ.get("MOONJUST_OFFICIAL_COMMIT", OFFICIAL_COMMIT)
    if official_commit != OFFICIAL_COMMIT:
        environment_errors.append(
            f"official benchmark commit must be {OFFICIAL_COMMIT}, observed {official_commit}"
        )
    candidate_commit = tool_output(["git", "rev-parse", "HEAD"])
    moon_toolchain = tool_output(["moon", "version", "--all"])
    merge_base = baseline_metadata(args.baseline_native)
    if args.baseline_native is not None:
        if merge_base is None:
            environment_errors.append("merge-base metadata.json is missing or invalid")
        else:
            native = merge_base.get("native", {})
            wasm = merge_base.get("wasm1", {})
            if not isinstance(merge_base.get("commit"), str):
                environment_errors.append("merge-base metadata commit is missing")
            if not isinstance(native, dict) or native.get("sha256") != sha256(args.baseline_native):
                environment_errors.append("merge-base native artifact hash does not match metadata")
            if not isinstance(wasm, dict) or wasm.get("sha256") != sha256(args.baseline_wasm):
                environment_errors.append("merge-base wasm artifact hash does not match metadata")
            if merge_base.get("moon") != moon_toolchain:
                environment_errors.append("merge-base and candidate MoonBit toolchains differ")
    args.raw_output.parent.mkdir(parents=True, exist_ok=True)
    results: dict[str, dict[str, object]] = {}
    fixtures_record: dict[str, dict[str, object]] = {}
    raw_rows: list[dict[str, object]] = []
    phase_durations: dict[str, float] = {"latency": 0.0, "memory": 0.0}
    early_stops: dict[str, bool] = {}
    cpu = machine["selected_cpu"] if isinstance(machine["selected_cpu"], int) else None
    with tempfile.TemporaryDirectory(prefix="moonjust-benchmark-") as raw:
        root = Path(raw)
        fixtures = write_fixtures(root)
        for workload, (fixture, arguments) in fixtures.items():
            fixtures_record[workload] = {
                "sha256": sha256(fixture),
                "bytes": fixture.stat().st_size,
                "arguments": arguments,
            }
            commands = {
                kind: command_for(kind, binary, fixture, arguments, moonrun, args.policy, cpu)
                for kind, binary in artifacts.items()
            }
            fixtures_record[workload]["commands"] = commands
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

    failures = list(environment_errors)
    for workload, values in results.items():
        for kind, summary in values.items():
            if float(summary["cv"]) > MAX_CV:
                failures.append(f"{workload}/{kind} CV {float(summary['cv']):.2%} exceeds 10%")
            rss_cv = summary["rss_cv"]
            if rss_cv is not None and float(rss_cv) > MAX_CV:
                failures.append(
                    f"{workload}/{kind} RSS CV {float(rss_cv):.2%} exceeds 10%"
                )
            if args.authoritative and summary["memory_observations"] == 0:
                failures.append(f"{workload}/{kind} has no RSS observations")
        official = values["official"]
        native = values["candidate-native"]
        if float(native["median_ms"]) > float(official["median_ms"]) * 1.5:
            failures.append(f"{workload}/native median exceeds 1.5x official")
        if float(native["p95_ms"]) > float(official["p95_ms"]) * 1.75:
            failures.append(f"{workload}/native p95 exceeds 1.75x official")
        if native["peak_rss_kib"] is not None and official["peak_rss_kib"] is not None and int(native["peak_rss_kib"]) > int(official["peak_rss_kib"]) * 2:
            failures.append(f"{workload}/native peak RSS exceeds 2x official")
        wasm = values["candidate-wasm"]
        if workload in WASM_BUDGETS_MS:
            median_budget, p95_budget = WASM_BUDGETS_MS[workload]
            if float(wasm["median_ms"]) > median_budget:
                failures.append(f"{workload}/wasm median {float(wasm['median_ms']):.2f}ms exceeds {median_budget:.0f}ms")
            if float(wasm["p95_ms"]) > p95_budget:
                failures.append(f"{workload}/wasm p95 {float(wasm['p95_ms']):.2f}ms exceeds {p95_budget:.0f}ms")
        if wasm["peak_rss_kib"] is not None and int(wasm["peak_rss_kib"]) > MAX_WASM_RSS_KIB:
            failures.append(f"{workload}/wasm peak RSS exceeds 128 MiB")
        if "baseline-native" in values:
            add_ratio_failure(failures, workload, native, values["baseline-native"])
            add_ratio_failure(failures, workload, wasm, values["baseline-wasm"])

    infrastructure_invalid = bool(environment_errors) or any(
        " CV " in item or "RSS observations" in item for item in failures
    )
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
            "merge_base_commit": merge_base.get("commit") if merge_base else None,
            "merge_base_moon": merge_base.get("moon") if merge_base else None,
        },
        "machine": machine,
        "moon": moon_toolchain,
        "configuration": {
            "warmups": args.warmups,
            "samples": args.samples,
            "memory_warmups": args.memory_warmups,
            "memory_samples": args.memory_samples,
            "seed": args.seed,
            "authoritative": args.authoritative,
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
        },
        "phases": {
            "durations_seconds": phase_durations,
            "latency_early_stops": early_stops,
        },
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
        print(f"performance gate: {failure}", file=sys.stderr)
    if failures and not args.report_only:
        return 1
    print(f"performance samples written to {args.output} and {args.raw_output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, ValueError) as error:
        print(f"performance gate error: {error}", file=sys.stderr)
        raise SystemExit(1)
