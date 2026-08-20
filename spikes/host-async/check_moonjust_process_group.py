#!/usr/bin/env python3
"""Stress MoonJust's narrow Unix process-group cleanup boundary."""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
SIGNAL_CASES = (
    ("SIGHUP", signal.SIGHUP),
    ("SIGINT", signal.SIGINT),
    ("SIGQUIT", signal.SIGQUIT),
    ("SIGTERM", signal.SIGTERM),
)


def process_group_snapshot(group: int) -> list[dict[str, Any]]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,pgid=,state=,command="],
        check=True,
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
        if pgid == group:
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


def pipe_holders(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not Path("/proc").is_dir():
        return []
    holders: list[dict[str, Any]] = []
    for row in rows:
        for fd in (Path("/proc") / str(row["pid"]) / "fd").glob("*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if target.startswith("pipe:"):
                holders.append(
                    {"pid": row["pid"], "fd": int(fd.name), "target": target}
                )
    return holders


def wait_for_file(path: Path, timeout: float) -> str:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            text = path.read_text(encoding="utf-8").strip()
        except OSError:
            text = ""
        if text:
            return text
        time.sleep(0.01)
    raise TimeoutError(f"process-group readiness file was not written: {path}")


def wait_for_group_exit(group: int, timeout: float) -> list[dict[str, Any]]:
    deadline = time.monotonic() + timeout
    while True:
        rows = process_group_snapshot(group)
        if not rows or time.monotonic() >= deadline:
            return rows
        time.sleep(0.02)


def terminate_group(group: int | None) -> None:
    if group is None or group <= 0:
        return
    try:
        os.killpg(group, signal.SIGKILL)
    except ProcessLookupError:
        pass


def validate_hidden_helper(executable: Path) -> dict[str, Any]:
    environment = os.environ.copy()
    environment["MOONJUST_INTERNAL_PROCESS_GROUP"] = "1"
    malformed = subprocess.run(
        [str(executable), "--moonjust-process-group-exec", ""],
        env=environment,
        check=False,
        capture_output=True,
        text=True,
        timeout=5.0,
    )
    if malformed.returncode != 127 or "failed (22)" not in malformed.stderr:
        raise RuntimeError(f"malformed helper payload was not rejected: {malformed}")
    argument = "a b|'quoted'|c\\d|中文"
    forwarded = subprocess.run(
        [
            str(executable),
            "--moonjust-process-group-exec",
            "/bin/sh",
            "-c",
            'test -z "${MOONJUST_INTERNAL_PROCESS_GROUP+x}" && printf %s "$1"',
            "moonjust-process-group",
            argument,
        ],
        env=environment,
        check=False,
        capture_output=True,
        text=True,
        timeout=5.0,
    )
    if forwarded.returncode != 0 or forwarded.stdout != argument or forwarded.stderr:
        raise RuntimeError(f"hidden helper argument forwarding drifted: {forwarded}")
    return {
        "schema_version": SCHEMA_VERSION,
        "record_type": "moonjust-process-group-helper",
        "malformed_returncode": malformed.returncode,
        "forwarded_argument": argument,
        "internal_environment_removed": True,
        "status": "passed",
    }


def run_case(
    executable: Path,
    iteration: int,
    signal_name: str,
    first_signal: signal.Signals,
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="moonjust-process-group-") as temporary:
        root = Path(temporary)
        ready = root / "ready"
        arguments = root / "arguments"
        justfile = root / "justfile"
        justfile.write_text(
            "default:\n"
            "  @test -z \"${MOONJUST_INTERNAL_PROCESS_GROUP+x}\"\n"
            "  @\"$MOONJUST_EXECUTABLE\" --version >/dev/null\n"
            "  @printf '%s' 'a b|c\\d|中文' > \"$MOONJUST_ARGUMENTS\"\n"
            "  @printf '%s %s\\n' \"$$\" \"$(ps -o pgid= -p $$ | tr -d ' ')\" "
            "> \"$MOONJUST_PROCESS_GROUP_READY\"; "
            "sh -c 'trap \"\" HUP INT QUIT; trap \"exit 0\" TERM; "
            "while :; do sleep 30; done' & wait\n",
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["MOONJUST_PROCESS_GROUP_READY"] = str(ready)
        environment["MOONJUST_ARGUMENTS"] = str(arguments)
        environment["MOONJUST_EXECUTABLE"] = str(executable)
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
        command_group: int | None = None
        try:
            fields = wait_for_file(ready, 5.0).split()
            if len(fields) != 2:
                raise RuntimeError(f"invalid process-group readiness record: {fields}")
            direct_pid, command_group = map(int, fields)
            if direct_pid != command_group:
                raise RuntimeError(
                    f"hidden helper did not create an owned process group: "
                    f"pid={direct_pid} pgid={command_group}"
                )
            if arguments.read_text(encoding="utf-8") != "a b|c\\d|中文":
                raise RuntimeError("process-group helper corrupted shell arguments")
            ready_rows = process_group_snapshot(command_group)
            ready_holders = pipe_holders(ready_rows)
            os.kill(process.pid, first_signal)
            if first_signal != signal.SIGTERM:
                os.kill(process.pid, first_signal)
                time.sleep(0.1)
            alive_after_first_signal = process.poll() is None
            if first_signal != signal.SIGTERM and not alive_after_first_signal:
                raise RuntimeError(
                    f"MoonJust exited after {signal_name} before the child completed"
                )
            if first_signal != signal.SIGTERM:
                os.kill(process.pid, signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=8.0)
            remaining = wait_for_group_exit(command_group, 2.0)
            expected_returncode = 128 + int(first_signal)
            if process.returncode != expected_returncode:
                raise RuntimeError(
                    f"first-signal exit mapping drifted: {process.returncode}; stderr={stderr!r}"
                )
            if remaining:
                raise RuntimeError(f"owned process group leaked: {remaining}")
            if f"interrupted by {signal_name}" not in stderr:
                raise RuntimeError(f"missing {signal_name} diagnostic: {stderr!r}")
            return {
                "schema_version": SCHEMA_VERSION,
                "record_type": "moonjust-process-group-case",
                "iteration": iteration,
                "first_signal": signal_name,
                "parent_pid": process.pid,
                "direct_pid": direct_pid,
                "process_group": command_group,
                "alive_after_first_signal": alive_after_first_signal,
                "returncode": process.returncode,
                "ready_processes": ready_rows,
                "ready_pipe_holders": ready_holders,
                "remaining_processes": remaining,
                "stdout": stdout,
                "stderr": stderr,
                "reader_eof": True,
                "status": "passed",
            }
        finally:
            terminate_group(command_group)
            if process.poll() is None:
                terminate_group(process.pid)
                process.communicate(timeout=5.0)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repetitions", type=int, default=20)
    args = parser.parse_args()
    if args.repetitions < 20:
        raise ValueError("process-group stress evidence requires at least 20 repetitions")
    executable = args.executable.resolve()
    if not executable.is_file():
        raise ValueError(f"MoonJust executable is missing: {executable}")
    helper = validate_hidden_helper(executable)
    records = [
        run_case(executable, index, signal_name, signal_number)
        for signal_name, signal_number in SIGNAL_CASES
        for index in range(args.repetitions)
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(
            json.dumps(record, sort_keys=True) + "\n"
            for record in [helper, *records]
        ),
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "schema_version": SCHEMA_VERSION,
                "record_type": "moonjust-process-group-summary",
                "cases": len(records),
                "repetitions_per_signal": args.repetitions,
                "status": "passed",
                "output": str(args.output),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
