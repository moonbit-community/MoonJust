#!/usr/bin/env python3
"""Collect MoonJust direct-child lifecycle evidence on Unix hosts."""

from __future__ import annotations

import argparse
import json
import os
import signal
import shutil
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 2
SCENARIOS = ("normal", "direct-cancel", "background", "detached")


def as_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def wait_for_file(path: Path, timeout: float) -> list[str]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            fields = path.read_text(encoding="utf-8").strip().split()
        except OSError:
            fields = []
        if fields:
            return fields
        time.sleep(0.01)
    raise TimeoutError(f"readiness record was not written: {path}")


def session_pids(session: int) -> list[int]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,pgid="],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    pids: list[int] = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) != 2:
            continue
        try:
            pid, pgid = map(int, fields)
        except ValueError:
            continue
        if pgid == session:
            pids.append(pid)
    return sorted(pids)


def marker_pids(
    name: str,
    value: str,
    session: int,
    expected_pids: tuple[int, ...] = (),
) -> list[int]:
    if Path("/proc").is_dir():
        marker = f"{name}={value}".encode() + b"\0"
        pids: list[int] = []
        for entry in Path("/proc").glob("[0-9]*"):
            try:
                environment = (entry / "environ").read_bytes()
            except OSError:
                continue
            if marker in environment:
                pids.append(int(entry.name))
        return sorted(pids)
    pids = set(session_pids(session))
    for pid in expected_pids:
        if pid <= 0:
            continue
        try:
            os.kill(pid, 0)
        except OSError:
            continue
        pids.add(pid)
    return sorted(pids)


def process_snapshot(pids: list[int]) -> list[dict[str, Any]]:
    if not pids:
        return []
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
    rows: list[dict[str, Any]] = []
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 4)
        if len(fields) != 5:
            continue
        try:
            pid, ppid, pgid = map(int, fields[:3])
        except ValueError:
            continue
        rows.append(
            {
                "pid": pid,
                "ppid": ppid,
                "pgid": pgid,
                "state": fields[3],
                "command": fields[4],
            }
        )
    return rows


def pipe_holders(pids: list[int]) -> list[dict[str, Any]]:
    if Path("/proc").is_dir():
        holders: list[dict[str, Any]] = []
        for pid in pids:
            for fd in (Path("/proc") / str(pid) / "fd").glob("*"):
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("pipe:"):
                    holders.append(
                        {"pid": pid, "fd": int(fd.name), "target": target}
                    )
        return sorted(holders, key=lambda row: (row["pid"], row["fd"]))

    lsof = shutil.which("lsof")
    if lsof is None or not pids:
        return []
    result = subprocess.run(
        [lsof, "-n", "-a", "-p", ",".join(map(str, pids)), "-F", "pfn"],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    holders = []
    pid = None
    fd = None
    for line in result.stdout.splitlines():
        if line.startswith("p"):
            try:
                pid = int(line[1:])
            except ValueError:
                pid = None
            fd = None
        elif line.startswith("f"):
            fd = line[1:]
        elif line.startswith("n") and pid is not None and fd is not None:
            target = line[1:]
            if target.startswith("->") or target.startswith("pipe:"):
                holders.append({"pid": pid, "fd": fd, "target": target})
    return sorted(holders, key=lambda row: (row["pid"], row["fd"]))


def snapshot(
    name: str,
    value: str,
    session: int,
    expected_pids: tuple[int, ...] = (),
) -> dict[str, Any]:
    pids = marker_pids(name, value, session, expected_pids)
    processes = process_snapshot(pids)
    return {
        "pids": pids,
        "processes": processes,
        "pipe_holders": pipe_holders(pids),
        "orphans": sorted(row["pid"] for row in processes if row["ppid"] == 1),
        "zombies": sorted(
            row["pid"] for row in processes if row["state"].startswith("Z")
        ),
    }


def terminate_pid(pid: int | None) -> None:
    if pid is None or pid <= 0:
        return
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def terminate_session(session: int) -> None:
    try:
        os.killpg(session, signal.SIGKILL)
    except ProcessLookupError:
        pass
    except PermissionError:
        for pid in session_pids(session):
            if pid != os.getpid():
                terminate_pid(pid)


def write_justfile(root: Path, scenario: str) -> tuple[Path, Path]:
    ready = root / "ready"
    justfile = root / "justfile"
    record = (
        "printf '%s %s %s %s\\n' \"$$\" \"$PPID\" "
        "\"$(ps -o pgid= -p $$ | tr -d ' ')\" \"-1\" > "
        '\"$MOONJUST_READY\"'
    )
    if scenario == "normal":
        body = f"{record}\n"
    elif scenario == "direct-cancel":
        body = f"{record}; exec sleep 30\n"
    elif scenario == "background":
        body = (
            "sleep 30 & child=$!; "
            "printf '%s %s %s %s\\n' \"$$\" \"$PPID\" "
            "\"$(ps -o pgid= -p $$ | tr -d ' ')\" \"$child\" > "
            '\"$MOONJUST_READY\"; wait\n'
        )
    elif scenario == "detached":
        body = (
            "python3 -c \"import os,time; os.setsid(); time.sleep(30)\" & child=$!; "
            "printf '%s %s %s %s\\n' \"$$\" \"$PPID\" "
            "\"$(ps -o pgid= -p $$ | tr -d ' ')\" \"$child\" > "
            '\"$MOONJUST_READY\"; wait\n'
        )
    else:
        raise ValueError(f"unknown lifecycle scenario: {scenario}")
    justfile.write_text(f"default:\n  @{body}", encoding="utf-8")
    return justfile, ready


def run_case(executable: Path, scenario: str) -> dict[str, Any]:
    marker_name = "MOONJUST_LIFECYCLE_RUN_ID"
    marker_value = f"{os.getpid()}-{time.time_ns()}"
    environment = os.environ.copy()
    environment[marker_name] = marker_value
    environment["MOONJUST_READY"] = ""
    with tempfile.TemporaryDirectory(prefix="moonjust-lifecycle-") as temporary:
        root = Path(temporary)
        justfile, ready = write_justfile(root, scenario)
        environment["MOONJUST_READY"] = str(ready)
        process = subprocess.Popen(
            [str(executable), "--justfile", str(justfile)],
            cwd=root,
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            start_new_session=True,
        )
        fields = wait_for_file(ready, 5.0)
        if len(fields) != 4:
            terminate_session(process.pid)
            process.communicate(timeout=5.0)
            raise RuntimeError(f"invalid readiness record: {fields}")
        direct_pid, direct_ppid, direct_pgid, descendant_pid = map(int, fields)
        expected_pids = (direct_pid, descendant_pid)
        ready_snapshot = snapshot(
            marker_name, marker_value, process.pid, expected_pids
        )
        timed_out = False
        stdout = ""
        stderr = ""
        try:
            if scenario == "normal":
                stdout, stderr = process.communicate(timeout=5.0)
            else:
                os.kill(process.pid, signal.SIGTERM)
                try:
                    stdout, stderr = process.communicate(timeout=2.0)
                except subprocess.TimeoutExpired as error:
                    timed_out = True
                    stdout = as_text(error.stdout)
                    stderr = as_text(error.stderr)
            before_cleanup = snapshot(
                marker_name, marker_value, process.pid, expected_pids
            )
            direct_child_reaped = direct_pid not in before_cleanup["pids"]
            return {
                "schema_version": SCHEMA_VERSION,
                "record_type": "moonjust-direct-child-case",
                "scenario": scenario,
                "parent_pid": process.pid,
                "direct_pid": direct_pid,
                "direct_ppid": direct_ppid,
                "direct_pgid": direct_pgid,
                "descendant_pid": descendant_pid,
                "returncode": process.returncode,
                "direct_child_reaped": direct_child_reaped,
                "direct_child_wait_status": {
                    "reaped": direct_child_reaped,
                    "mapped_exit_status": process.returncode,
                },
                "timed_out": timed_out,
                "reader_eof": not timed_out,
                "ready": ready_snapshot,
                "before_cleanup": before_cleanup,
                "stdout": stdout,
                "stderr": stderr,
                "status": "passed",
            }
        finally:
            terminate_pid(descendant_pid)
            terminate_session(process.pid)
            if process.poll() is None:
                process.communicate(timeout=5.0)


def validate(records: list[dict[str, Any]]) -> None:
    by_scenario = {record["scenario"]: record for record in records}
    normal = by_scenario["normal"]
    if (
        normal["returncode"] != 0
        or normal["timed_out"]
        or not normal["direct_child_reaped"]
        or normal["before_cleanup"]["processes"]
    ):
        raise RuntimeError("normal direct-child lifecycle did not complete cleanly")

    cancelled = by_scenario["direct-cancel"]
    if (
        cancelled["returncode"] != 143
        or cancelled["timed_out"]
        or not cancelled["direct_child_reaped"]
    ):
        raise RuntimeError("direct-child cancellation did not wait and reap")

    for scenario in ("background", "detached"):
        record = by_scenario[scenario]
        if not record["timed_out"] or not record["direct_child_reaped"]:
            raise RuntimeError(
                f"{scenario} did not expose the expected indirect descendant observation"
            )
        if record["reader_eof"] or not record["before_cleanup"]["pipe_holders"]:
            raise RuntimeError(f"{scenario} lost shared-pipe holder evidence")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    executable = args.executable.resolve()
    if not executable.is_file():
        raise ValueError(f"MoonJust executable is missing: {executable}")
    records = [run_case(executable, scenario) for scenario in SCENARIOS]
    validate(records)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(json.dumps(record, sort_keys=True) + "\n" for record in records),
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "schema_version": SCHEMA_VERSION,
                "record_type": "moonjust-direct-child-summary",
                "cases": len(records),
                "status": "passed",
                "output": str(args.output),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
