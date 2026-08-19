#!/usr/bin/env python3
"""Reproducible end-to-end release benchmark with separate latency/RSS passes."""

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
import threading
import time
from pathlib import Path
from typing import Iterable


SCHEMA_VERSION = 2
OFFICIAL_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
DEFAULT_SEED = 1_570
MAX_CV = 0.10
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


def process_tree_rss_kib(root_pid: int) -> int | None:
    if platform.system() != "Linux":
        return None
    parent: dict[int, int] = {}
    rss: dict[int, int] = {}
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            status = (entry / "status").read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        pid = int(entry.name)
        for line in status.splitlines():
            if line.startswith("PPid:"):
                parent[pid] = int(line.split()[1])
            elif line.startswith("VmRSS:"):
                rss[pid] = int(line.split()[1])
    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, ppid in parent.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return sum(rss.get(pid, 0) for pid in descendants)


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


def run_memory_sample(command: list[str], cwd: Path) -> int | None:
    if platform.system() == "Linux" and Path("/usr/bin/time").is_file():
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
    if process.returncode != 0:
        raise RuntimeError(
            f"benchmark command failed ({process.returncode}): {command!r}\n"
            + stderr.decode(errors="replace")[:2000]
        )
    return peak


def percentile95(values: list[float]) -> float:
    return sorted(values)[math.ceil(len(values) * 0.95) - 1]


def coefficient_of_variation(values: list[float]) -> float | None:
    if not values:
        return None
    mean = statistics.fmean(values)
    return statistics.pstdev(values) / mean if mean else 0.0


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


def append_raw(path: Path, row: dict[str, object]) -> None:
    with path.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(row, sort_keys=True) + "\n")


def collect_phase(
    phase: str,
    workload: str,
    commands: dict[str, list[str]],
    cwd: Path,
    warmups: int,
    samples: int,
    seed: int,
    raw_output: Path,
) -> dict[str, list[float] | list[int | None]]:
    kinds = tuple(commands)
    for order in balanced_orders(kinds, warmups, seed):
        for kind in order:
            if phase == "latency":
                run_latency_sample(commands[kind], cwd)
            else:
                run_memory_sample(commands[kind], cwd)
    collected: dict[str, list[float] | list[int | None]] = {kind: [] for kind in kinds}
    for iteration, order in enumerate(balanced_orders(kinds, samples, seed + 1)):
        for position, kind in enumerate(order):
            if phase == "latency":
                value: float | int | None = run_latency_sample(commands[kind], cwd)
                field = "elapsed_ms"
            else:
                value = run_memory_sample(commands[kind], cwd)
                field = "peak_rss_kib"
            collected[kind].append(value)  # type: ignore[arg-type]
            append_raw(
                raw_output,
                {
                    "schema_version": SCHEMA_VERSION,
                    "phase": phase,
                    "workload": workload,
                    "iteration": iteration,
                    "position": position,
                    "kind": kind,
                    field: value,
                },
            )
    return collected


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
    parser.add_argument("--memory-warmups", type=int, default=5)
    parser.add_argument("--memory-samples", type=int, default=30)
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
    if min(args.warmups, args.memory_warmups) < 0 or min(args.samples, args.memory_samples) < 2:
        raise RuntimeError("benchmark requires non-negative warmups and at least 2 samples per pass")
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
    args.raw_output.write_text("", encoding="utf-8")
    results: dict[str, dict[str, object]] = {}
    fixtures_record: dict[str, dict[str, object]] = {}
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
            latency = collect_phase(
                "latency", workload, commands, root, args.warmups, args.samples,
                args.seed + len(results) * 100, args.raw_output,
            )
            memory = collect_phase(
                "memory", workload, commands, root, args.memory_warmups, args.memory_samples,
                args.seed + len(results) * 100 + 50, args.raw_output,
            )
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
