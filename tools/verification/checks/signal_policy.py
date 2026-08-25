#!/usr/bin/env python3
"""Record the async-only direct-child signal and pipe lifecycle policy."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
SCENARIOS = ("normal", "direct-signal", "cancellation", "background", "detached")


def load_lifecycle_helpers() -> Any:
    path = Path(__file__).resolve().parents[3] / "spikes/host-async/check_moonjust_process_lifecycle.py"
    spec = importlib.util.spec_from_file_location("moonjust_lifecycle_helpers", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load lifecycle helpers: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_justfile(root: Path, scenario: str) -> tuple[Path, Path]:
    ready = root / "ready"
    justfile = root / "justfile"
    record = (
        "printf '%s %s %s %s\\n' \"$$\" \"$PPID\" "
        "\"$(ps -o pgid= -p $$ | tr -d ' ')\" \"-1\" > "
        '"$MOONJUST_READY"'
    )
    if scenario == "normal":
        body = record
    elif scenario == "direct-signal":
        body = f"{record}; kill -TERM \"$$\""
    elif scenario == "cancellation":
        body = f"{record}; exec sleep 30"
    elif scenario == "background":
        body = (
            "sleep 30 & child=$!; "
            "printf '%s %s %s %s\\n' \"$$\" \"$PPID\" "
            "\"$(ps -o pgid= -p $$ | tr -d ' ')\" \"$child\" > "
            '"$MOONJUST_READY"; wait'
        )
    elif scenario == "detached":
        body = (
            "python3 -c \"import os,time; os.setsid(); time.sleep(30)\" & child=$!; "
            "printf '%s %s %s %s\\n' \"$$\" \"$PPID\" "
            "\"$(ps -o pgid= -p $$ | tr -d ' ')\" \"$child\" > "
            '"$MOONJUST_READY"; wait'
        )
    else:
        raise ValueError(f"unknown signal policy scenario: {scenario}")
    justfile.write_text(f"default:\n  @{body}\n", encoding="utf-8")
    return justfile, ready


def run_case(executable: Path, scenario: str, helpers: Any) -> dict[str, Any]:
    marker_name = "MOONJUST_SIGNAL_POLICY_RUN_ID"
    marker_value = f"{os.getpid()}-{time.time_ns()}-{scenario}"
    environment = os.environ.copy()
    environment[marker_name] = marker_value
    with tempfile.TemporaryDirectory(prefix="moonjust-signal-policy-") as raw:
        root = Path(raw)
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
        try:
            fields = helpers.wait_for_file(ready, 5.0)
            if len(fields) != 4:
                raise RuntimeError(f"invalid readiness record: {fields}")
            direct_pid, direct_ppid, direct_pgid, descendant_pid = map(int, fields)
            expected_pids = (direct_pid, descendant_pid)
            ready_snapshot = helpers.snapshot(
                marker_name, marker_value, process.pid, expected_pids
            )
            if scenario == "normal" or scenario == "direct-signal":
                stdout, stderr = process.communicate(timeout=5.0)
                timed_out = False
            else:
                os.kill(process.pid, signal.SIGTERM)
                try:
                    # The async process adapter allows five seconds for graceful
                    # cancellation before its forced termination fallback.
                    stdout, stderr = process.communicate(timeout=8.0)
                    timed_out = False
                except subprocess.TimeoutExpired as error:
                    stdout = helpers.as_text(error.stdout)
                    stderr = helpers.as_text(error.stderr)
                    timed_out = True
            before_cleanup = helpers.snapshot(
                marker_name, marker_value, process.pid, expected_pids
            )
            direct_child_reaped = direct_pid not in before_cleanup["pids"]
            return {
                "schema_version": SCHEMA_VERSION,
                "policy": "async-only",
                "scenario": scenario,
                "parent_pid": process.pid,
                "direct_pid": direct_pid,
                "direct_ppid": direct_ppid,
                "direct_pgid": direct_pgid,
                "descendant_pid": descendant_pid,
                "returncode": process.returncode,
                "direct_child_wait_status": {
                    "reaped": direct_child_reaped,
                    "mapped_exit_status": process.returncode,
                },
                "timed_out": timed_out,
                "reader_eof": not timed_out,
                "ready": ready_snapshot,
                "before_cleanup": before_cleanup,
                "pipe_holders": before_cleanup["pipe_holders"],
                "approved_observation": scenario in {"background", "detached"},
                "status": "passed" if direct_child_reaped and not timed_out else "observation",
                "stdout": stdout,
                "stderr": stderr,
            }
        finally:
            try:
                helpers.terminate_pid(locals().get("descendant_pid"))
                helpers.terminate_session(process.pid)
                if process.poll() is None:
                    process.communicate(timeout=5.0)
            except (OSError, subprocess.TimeoutExpired):
                process.kill()
                process.communicate()


def validate(records: list[dict[str, Any]]) -> None:
    by_scenario = {record["scenario"]: record for record in records}
    if set(by_scenario) != set(SCENARIOS):
        raise RuntimeError("signal policy scenario set is incomplete")
    for scenario in ("normal", "direct-signal", "cancellation"):
        record = by_scenario[scenario]
        if record["timed_out"] or not record["direct_child_wait_status"]["reaped"]:
            raise RuntimeError(f"{scenario} direct-child wait/reap failed")
    for scenario in ("background", "detached"):
        record = by_scenario[scenario]
        if not record["direct_child_wait_status"]["reaped"]:
            raise RuntimeError(f"{scenario} direct child was not reaped")
        if not record["reader_eof"] and not record["pipe_holders"]:
            raise RuntimeError(f"{scenario} lacks shared-pipe observation")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--executable", type=Path)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("_build/upstream-harness/signal-policy.jsonl"),
    )
    args = parser.parse_args()
    if os.name == "nt":
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(
                {
                    "schema_version": SCHEMA_VERSION,
                    "policy": "async-only",
                    "status": "not-applicable",
                    "platform": "windows",
                },
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        print("signal policy: not-applicable on Windows")
        return 0
    executable = args.executable
    if executable is None:
        candidates = (
            Path("_build/native/debug/build/cmd/just/just.exe"),
            Path("_build/native/debug/build/cmd/just/just"),
        )
        executable = next((candidate for candidate in candidates if candidate.is_file()), candidates[0])
    executable = executable.resolve()
    if not executable.is_file():
        print(f"signal policy executable is missing: {executable}", file=sys.stderr)
        return 1
    helpers = load_lifecycle_helpers()
    try:
        records = [run_case(executable, scenario, helpers) for scenario in SCENARIOS]
        validate(records)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"signal policy failed: {error}", file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        "".join(json.dumps(record, sort_keys=True) + "\n" for record in records),
        encoding="utf-8",
    )
    print(f"signal policy: {len(records)} scenarios recorded at {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
