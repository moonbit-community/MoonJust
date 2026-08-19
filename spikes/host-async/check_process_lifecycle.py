#!/usr/bin/env python3
"""Collect signal, process, and pipe lifecycle evidence for async 0.21.0."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import selectors
import signal
import subprocess
import time
import uuid
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
SCENARIOS = ("direct", "shell-exec", "shell-foreground", "shell-descendant")
OBSERVATION_ERRORS: list[str] = []


def encode(record: dict[str, Any]) -> str:
    return json.dumps(record, sort_keys=True, separators=(",", ":"))


def as_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_ready_line(process: subprocess.Popen[str], timeout: float) -> str:
    assert process.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    try:
        events = selector.select(timeout)
        if not events:
            raise TimeoutError("process did not emit readiness event")
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(
                f"process exited before readiness event: returncode={process.poll()}"
            )
        return line
    finally:
        selector.close()


def linux_marker_pids(name: str, value: str) -> list[int]:
    marker = f"{name}={value}".encode() + b"\0"
    matches: list[int] = []
    for entry in Path("/proc").glob("[0-9]*"):
        try:
            environment = (entry / "environ").read_bytes()
        except OSError:
            continue
        if marker in environment:
            matches.append(int(entry.name))
    return sorted(matches)


def group_pids(pgid: int) -> list[int]:
    try:
        result = subprocess.run(
            ["ps", "-axo", "pid=,pgid="],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as error:
        message = f"process observation unavailable: {error}"
        if message not in OBSERVATION_ERRORS:
            OBSERVATION_ERRORS.append(message)
        return []
    matches: list[int] = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) != 2:
            continue
        try:
            pid, candidate = map(int, fields)
        except ValueError:
            continue
        if candidate == pgid:
            matches.append(pid)
    return sorted(matches)


def marker_pids(name: str, value: str, pgid: int) -> list[int]:
    if platform.system() == "Linux":
        return linux_marker_pids(name, value)
    return group_pids(pgid)


def process_snapshot(pids: list[int]) -> list[dict[str, Any]]:
    if not pids:
        return []
    try:
        result = subprocess.run(
            [
                "ps",
                "-o",
                "pid=,ppid=,pgid=,state=,command=",
                "-p",
                ",".join(map(str, pids)),
            ],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as error:
        message = f"process observation unavailable: {error}"
        if message not in OBSERVATION_ERRORS:
            OBSERVATION_ERRORS.append(message)
        return []
    rows: list[dict[str, Any]] = []
    pattern = re.compile(r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\S+)\s+(.*)$")
    for line in result.stdout.splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        rows.append(
            {
                "pid": int(match.group(1)),
                "ppid": int(match.group(2)),
                "pgid": int(match.group(3)),
                "state": match.group(4),
                "command": match.group(5),
            }
        )
    return rows


def linux_pipe_holders(pids: list[int]) -> list[dict[str, Any]]:
    if platform.system() != "Linux":
        return []
    holders: list[dict[str, Any]] = []
    for pid in pids:
        for fd in (Path("/proc") / str(pid) / "fd").glob("*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("pipe:"):
                holders.append({"pid": pid, "fd": int(fd.name), "target": target})
    return sorted(holders, key=lambda row: (row["pid"], row["fd"]))


def snapshot(name: str, value: str, pgid: int) -> dict[str, Any]:
    pids = marker_pids(name, value, pgid)
    processes = process_snapshot(pids)
    return {
        "pids": pids,
        "processes": processes,
        "pipe_holders": linux_pipe_holders(pids),
        "orphans": sorted(row["pid"] for row in processes if row["ppid"] == 1),
        "zombies": sorted(
            row["pid"] for row in processes if row["state"].startswith("Z")
        ),
    }


def kill_test_group(pgid: int) -> None:
    try:
        os.killpg(pgid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def wait_for_cleanup(name: str, value: str, pgid: int) -> list[int]:
    deadline = time.monotonic() + 2.0
    while True:
        pids = marker_pids(name, value, pgid)
        if not pids or time.monotonic() >= deadline:
            return pids
        time.sleep(0.02)


def parse_events(stdout: str) -> tuple[list[dict[str, Any]], list[str]]:
    events: list[dict[str, Any]] = []
    invalid: list[str] = []
    for line in stdout.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            invalid.append(line)
            continue
        if isinstance(value, dict) and isinstance(value.get("event"), str):
            events.append(value)
        else:
            invalid.append(line)
    return events, invalid


def run_case(
    executable: Path,
    scenario: str,
    mode: str,
    timeout: float,
) -> dict[str, Any]:
    marker_name = "MOONJUST_LIFECYCLE_RUN_ID"
    marker_value = uuid.uuid4().hex
    environment = os.environ.copy()
    environment[marker_name] = marker_value
    environment["MOONJUST_LIFECYCLE_SIGNAL_MODE"] = mode
    process = subprocess.Popen(
        [str(executable), "parent", scenario],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
        env=environment,
        start_new_session=True,
    )
    pgid = process.pid
    ready_line = ""
    stdout = ""
    stderr = ""
    timed_out = False
    try:
        ready_line = read_ready_line(process, timeout=5.0)
        ready_snapshot = snapshot(marker_name, marker_value, pgid)
        os.kill(process.pid, signal.SIGINT)
        time.sleep(0.25)
        alive_after_first_signal = process.poll() is None
        after_first_signal = snapshot(marker_name, marker_value, pgid)
        if alive_after_first_signal:
            os.kill(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
            before_cleanup = snapshot(marker_name, marker_value, pgid)
        except subprocess.TimeoutExpired as error:
            timed_out = True
            stdout = as_text(error.stdout)
            stderr = as_text(error.stderr)
            before_cleanup = snapshot(marker_name, marker_value, pgid)
            kill_test_group(pgid)
            extra_stdout, extra_stderr = process.communicate(timeout=5.0)
            if not stdout:
                stdout = extra_stdout
            if not stderr:
                stderr = extra_stderr
    except BaseException:
        kill_test_group(pgid)
        process.communicate(timeout=5.0)
        raise
    finally:
        kill_test_group(pgid)
    remaining = wait_for_cleanup(marker_name, marker_value, pgid)
    combined_stdout = ready_line + stdout
    events, invalid_lines = parse_events(combined_stdout)
    return {
        "schema_version": SCHEMA_VERSION,
        "record_type": "lifecycle-case",
        "mode": mode,
        "scenario": scenario,
        "signals": ["SIGINT", "SIGTERM"] if alive_after_first_signal else ["SIGINT"],
        "returncode": process.returncode,
        "timed_out": timed_out,
        "alive_after_first_signal": alive_after_first_signal,
        "ready": ready_snapshot,
        "after_first_signal": after_first_signal,
        "before_cleanup": before_cleanup,
        "remaining_after_cleanup": remaining,
        "events": events,
        "invalid_stdout_lines": invalid_lines,
        "stderr": stderr,
    }


def async_cause_report(async_root: Path) -> dict[str, Any]:
    signal_source = async_root / "src/internal/event_loop/signal.mbt"
    event_loop_source = async_root / "src/internal/event_loop/event_loop.mbt"
    coroutine_source = async_root / "src/internal/coroutine/coroutine.mbt"
    cancellation_source = async_root / "src/process/cancellation.mbt"
    sources = [
        signal_source,
        event_loop_source,
        coroutine_source,
        cancellation_source,
    ]
    missing = [str(path) for path in sources if not path.is_file()]
    if missing:
        raise RuntimeError(f"async lifecycle sources are missing: {missing}")
    signal_text = signal_source.read_text(encoding="utf-8")
    event_loop_text = event_loop_source.read_text(encoding="utf-8")
    coroutine_text = coroutine_source.read_text(encoding="utf-8")
    cancellation_text = cancellation_source.read_text(encoding="utf-8")
    checks = {
        "event_loop_preserves_signal": "KilledBySignal(Int)" in signal_text,
        "event_loop_cancels_main_without_cause": "main.cancel()" in event_loop_text,
        "coroutine_stores_boolean_cancelled": "mut cancelled : Bool" in coroutine_text,
        "process_handler_receives_pid_only": (
            "CancellationHandler(async (Int) -> Unit)" in cancellation_text
        ),
    }
    if not all(checks.values()):
        raise RuntimeError(f"async cancellation source contract drifted: {checks}")
    return {
        "schema_version": SCHEMA_VERSION,
        "record_type": "async-cause-path",
        "checks": checks,
        "cause_path": [
            "KilledBySignal(signal)",
            "Coroutine::cancel() stores Bool",
            "Process CancellationHandler receives PID only",
        ],
        "source_sha256": {str(path.relative_to(async_root)): sha256(path) for path in sources},
    }


def validate_linux(records: list[dict[str, Any]]) -> None:
    by_key = {(record["mode"], record["scenario"]): record for record in records}
    for scenario in ("direct", "shell-exec", "shell-foreground"):
        record = by_key[("observe", scenario)]
        event_names = [event["event"] for event in record["events"]]
        parent_signals = [
            event["signal"]
            for event in record["events"]
            if event["event"] == "parent-signal"
        ]
        if (
            not record["alive_after_first_signal"]
            or record["timed_out"]
            or record["returncode"] != 0
        ):
            raise RuntimeError(f"observe/{scenario} did not wait then close cleanly")
        if parent_signals != ["SIGINT", "SIGTERM"]:
            raise RuntimeError(f"observe/{scenario} signal order drifted")
        required_events = {
            "direct-forward",
            "process-wait-complete",
            "pipe-reader-eof",
            "pipe-reader-joined",
            "parent-complete",
        }
        if not required_events.issubset(event_names):
            raise RuntimeError(f"observe/{scenario} lifecycle events are incomplete")
        if event_names.index("pipe-reader-eof") > event_names.index("pipe-reader-joined"):
            raise RuntimeError(f"observe/{scenario} joined pipe reader before EOF")
        if (
            record["ready"]["orphans"]
            or record["ready"]["zombies"]
            or record["after_first_signal"]["orphans"]
            or record["after_first_signal"]["zombies"]
            or record["before_cleanup"]["processes"]
            or record["remaining_after_cleanup"]
        ):
            raise RuntimeError(f"observe/{scenario} leaked processes")
        if record["invalid_stdout_lines"] or record["stderr"]:
            raise RuntimeError(f"observe/{scenario} emitted invalid evidence")
    descendant = by_key[("observe", "shell-descendant")]
    if not descendant["timed_out"]:
        raise RuntimeError("shell descendant unexpectedly closed all inherited pipes")
    descendant_events = [event["event"] for event in descendant["events"]]
    if "process-wait-complete" not in descendant_events:
        raise RuntimeError("direct shell did not terminate before descendant timeout")
    if "pipe-reader-eof" in descendant_events:
        raise RuntimeError("descendant retained process but pipe reader reported EOF")
    if (
        not descendant["before_cleanup"]["orphans"]
        or not descendant["before_cleanup"]["pipe_holders"]
    ):
        raise RuntimeError("shell descendant timeout lacks pipe-holder evidence")
    global_direct = by_key[("global", "direct")]
    if (
        global_direct["alive_after_first_signal"]
        or global_direct["timed_out"]
        or global_direct["returncode"] != -signal.SIGINT
    ):
        raise RuntimeError("async global SIGINT did not cancel the main task")
    cancellation_events = [
        event for event in global_direct["events"] if event["event"] == "cancel-handler"
    ]
    if len(cancellation_events) != 1:
        raise RuntimeError("global cancellation did not reach Process cancellation handler")
    if cancellation_events[0].get("available_cause_fields") != ["pid"]:
        raise RuntimeError("Process cancellation cause surface changed")
    if global_direct["before_cleanup"]["processes"]:
        raise RuntimeError("global cancellation returned before direct child cleanup")
    late_direct = by_key[("late", "direct")]
    late_events = [event["event"] for event in late_direct["events"]]
    late_signals = [
        event["signal"]
        for event in late_direct["events"]
        if event["event"] == "parent-signal"
    ]
    if (
        not late_direct["alive_after_first_signal"]
        or late_direct["timed_out"]
        or late_direct["returncode"] != 0
        or late_signals != ["SIGINT", "SIGTERM"]
        or "direct-forward" not in late_events
        or "process-wait-complete" not in late_events
        or "pipe-reader-eof" not in late_events
        or "pipe-reader-joined" not in late_events
        or "parent-complete" not in late_events
    ):
        raise RuntimeError(
            "late signal configuration did not preserve observed lifecycle"
        )
    if (
        late_direct["ready"]["orphans"]
        or late_direct["after_first_signal"]["orphans"]
        or late_direct["before_cleanup"]["processes"]
        or late_direct["remaining_after_cleanup"]
    ):
        raise RuntimeError("late signal configuration leaked processes")
    for record in records:
        if record["remaining_after_cleanup"]:
            raise RuntimeError(
                f"probe cleanup leaked processes for {record['mode']}/{record['scenario']}"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--async-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--assert-linux", action="store_true")
    args = parser.parse_args()
    if not args.executable.is_file():
        raise RuntimeError(f"lifecycle probe is missing: {args.executable}")
    records = [
        run_case(args.executable.resolve(), scenario, "observe", timeout=2.0)
        for scenario in SCENARIOS
    ]
    records.append(run_case(args.executable.resolve(), "direct", "late", timeout=2.0))
    records.append(run_case(args.executable.resolve(), "direct", "global", timeout=2.0))
    cause = async_cause_report(args.async_root.resolve())
    if args.assert_linux:
        if platform.system() != "Linux":
            raise RuntimeError("--assert-linux requires Linux")
        validate_linux(records)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(encode(record) + "\n" for record in [cause, *records]),
        encoding="utf-8",
    )
    summary = {
        "schema_version": SCHEMA_VERSION,
        "record_type": "lifecycle-summary",
        "host": f"{platform.system().lower()}-{platform.machine().lower()}",
        "cases": len(records),
        "linux_assertions": args.assert_linux,
        "output": str(args.output),
        "status": "infrastructure-invalid" if OBSERVATION_ERRORS else "passed",
        "observation_errors": OBSERVATION_ERRORS,
    }
    print(encode(summary))
    return 2 if OBSERVATION_ERRORS else 0


if __name__ == "__main__":
    raise SystemExit(main())
