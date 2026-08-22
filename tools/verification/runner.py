#!/usr/bin/env python3
"""MoonJust's single, provenance-first verification and measurement runner.

The runner deliberately keeps orchestration in one place.  Existing shell and
Python programs are treated as implementation probes; CI and local users only
call this module.  Every invocation records the exact checked-out commit,
build inputs, commands, and artifact hashes in evidence schema v2.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Iterable, Sequence


RUNNER_VERSION = "2.0"
EVIDENCE_SCHEMA_VERSION = 2
OFFICIAL_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
OFFICIAL_VERSION = "1.57.0"
Command = tuple[str, ...]


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")


def command(*parts: str) -> Command:
    return tuple(parts)


def git_output(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=repo, check=True, capture_output=True, text=True
    )
    return result.stdout.strip()


def source_identity(repo: Path) -> dict[str, str]:
    return {
        "commit_sha": git_output(repo, "rev-parse", "HEAD"),
        "tree_sha": git_output(repo, "rev-parse", "HEAD^{tree}"),
    }


def expected_commit(args_expected: str | None = None) -> str | None:
    if args_expected:
        return args_expected
    # GitHub's pull_request checkout defaults to a synthetic merge commit. CI
    # passes the head SHA explicitly; never silently substitute GITHUB_SHA.
    return os.environ.get("MOONJUST_EXPECTED_HEAD_SHA")


def toolchain(repo: Path) -> tuple[str, str]:
    value = subprocess.run(
        ["moon", "version", "--all"], cwd=repo, check=True, capture_output=True, text=True
    ).stdout.strip()
    return value, sha256_bytes(value.encode("utf-8"))


def dependency_fingerprint(repo: Path) -> tuple[str, list[dict[str, str]]]:
    files = sorted(
        path
        for pattern in ("moon.mod", "moon.lock", "moon.pkg", "moon.pkg.json")
        for path in repo.rglob(pattern)
        if ".mooncakes" not in path.parts and "_build" not in path.parts
    )
    records: list[dict[str, str]] = []
    for path in files:
        records.append({"path": path.relative_to(repo).as_posix(), "sha256": sha256(path)})
    return sha256_bytes(canonical(records)), records


def environment_digest(env: dict[str, str]) -> str:
    # Never persist secret values. These fields affect reproducibility and are
    # safe to record as names/values after the command has run.
    selected = {
        key: env.get(key, "")
        for key in (
            "CI",
            "GITHUB_ACTIONS",
            "GITHUB_RUN_ID",
            "GITHUB_RUN_ATTEMPT",
            "GITHUB_REF",
            "GITHUB_WORKFLOW",
            "MOONJUST_EXPECTED_HEAD_SHA",
            "MOONJUST_PERF_CPU",
            "SOURCE_DATE_EPOCH",
            "ZERO_AR_DATE",
        )
        if key in env
    }
    return sha256_bytes(canonical(selected))


def host_identity() -> dict[str, str]:
    return {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python": platform.python_version(),
    }


def relative_command(repo: Path, argv: Sequence[str]) -> list[str]:
    result: list[str] = []
    for item in argv:
        try:
            path = Path(item)
            if path.is_absolute():
                result.append(str(path.relative_to(repo)))
            else:
                result.append(item)
        except ValueError:
            result.append(item)
    return result


def executable_command(argv: Command) -> Command:
    """Run shell probes through Git Bash on Windows, preserving direct exec elsewhere."""
    if platform.system() == "Windows" and argv and argv[0].lower().endswith(".sh"):
        git_bash = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git" / "bin" / "bash.exe"
        return (str(git_bash) if git_bash.is_file() else "bash", *argv)
    return argv


def artifact_record(path: Path, repo: Path) -> dict[str, object]:
    record: dict[str, object] = {"path": str(path), "exists": path.is_file()}
    if path.is_file():
        record.update(
            {
                "relative_path": path.relative_to(repo).as_posix()
                if path.is_relative_to(repo)
                else str(path),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
        )
    return record


def build_key(fields: dict[str, object]) -> str:
    required = (
        "commit_sha",
        "tree_sha",
        "target",
        "host_triple",
        "profile",
        "compiler_flags",
        "moon_toolchain_digest",
        "dependency_graph_digest",
        "source_input_digest",
    )
    missing = [name for name in required if name not in fields]
    if missing:
        raise ValueError("build key is missing fields: " + ", ".join(missing))
    return sha256_bytes(canonical({name: fields[name] for name in required}))


class BuildRegistry:
    """Content-addressed build records with exact-SHA reuse boundaries."""

    def __init__(self, root: Path, repo: Path | None = None) -> None:
        self.root = root
        self.repo = repo
        self.root.mkdir(parents=True, exist_ok=True)

    def _marker(self, key: str) -> Path:
        return self.root / f"{key}.json"

    def claim(self, source_sha: str, target: str, profile: str) -> tuple[str, bool]:
        """Allocate a deterministic registry key for lightweight callers.

        Full builds must use :meth:`ensure`; this helper remains useful for
        tests and tools that only need a reservation without producing an
        artifact.
        """
        fields = {
            "commit_sha": source_sha,
            "tree_sha": "unknown",
            "target": target,
            "host_triple": "unknown",
            "profile": profile,
            "compiler_flags": "",
            "moon_toolchain_digest": "unknown",
            "dependency_graph_digest": "unknown",
            "source_input_digest": "unknown",
        }
        key = build_key(fields)
        marker = self._marker(key)
        if marker.is_file():
            return key, False
        marker.write_text(
            json.dumps({"schema_version": EVIDENCE_SCHEMA_VERSION, "key": key, **fields}, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return key, True

    def inspect(self) -> list[dict[str, object]]:
        records: list[dict[str, object]] = []
        for marker in sorted(self.root.glob("*.json")):
            try:
                value = json.loads(marker.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(value, dict):
                records.append(value)
        return records

    def gc(self) -> int:
        removed = 0
        for marker in self.root.glob("*.tmp"):
            marker.unlink(missing_ok=True)
            removed += 1
        return removed

    def ensure(
        self,
        fields_or_source: dict[str, object] | str,
        *args: object,
        execute: bool = True,
    ) -> dict[str, object]:
        # Accept the pre-registry-v2 call shape for local tool tests while all
        # production callers use the complete field map.  This is internal
        # Python compatibility, not a public shell entry point.
        if isinstance(fields_or_source, dict):
            fields = dict(fields_or_source)
            if len(args) < 3:
                raise TypeError("ensure(fields, command, artifact, cwd, ...) requires four arguments")
            command_line = args[0]
            artifact = args[1]
            cwd = args[2]
            if len(args) >= 4:
                execute = bool(args[3])
        else:
            if len(args) < 7:
                raise TypeError("legacy ensure requires source, target, profile, command, artifact, cwd, toolchain, execute")
            source_sha = fields_or_source
            target, profile, command_line, artifact, cwd, toolchain_value, legacy_execute = args[:7]
            fields = {
                "commit_sha": source_sha,
                "tree_sha": "unknown",
                "target": target,
                "host_triple": "unknown",
                "profile": profile,
                "compiler_flags": "",
                "moon_toolchain_digest": sha256_bytes(str(toolchain_value).encode()),
                "moon_toolchain": str(toolchain_value),
                "dependency_graph_digest": "unknown",
                "source_input_digest": "unknown",
            }
            execute = bool(legacy_execute)
        if not isinstance(command_line, tuple):
            command_line = tuple(str(part) for part in command_line)  # type: ignore[arg-type]
        if not isinstance(artifact, Path) or not isinstance(cwd, Path):
            raise TypeError("artifact and cwd must be pathlib.Path values")
        key = build_key(fields)
        marker = self._marker(key)
        existing: dict[str, object] = {}
        if marker.is_file():
            try:
                parsed = json.loads(marker.read_text(encoding="utf-8"))
                if isinstance(parsed, dict):
                    existing = parsed
            except json.JSONDecodeError:
                pass
        existing_artifact = existing.get("artifact")
        existing_artifact_record = existing_artifact if isinstance(existing_artifact, dict) else {}
        valid = (
            existing.get("schema_version") == EVIDENCE_SCHEMA_VERSION
            and existing.get("key") == key
            and existing.get("commit_sha") == fields["commit_sha"]
            and existing.get("command") == list(command_line)
            and artifact.is_file()
            and existing_artifact_record.get("sha256") == sha256(artifact)
        )
        built = False
        build_error: subprocess.CalledProcessError | None = None
        if not valid:
            if execute:
                try:
                    subprocess.run(command_line, cwd=cwd, check=True)
                    if not artifact.is_file():
                        raise RuntimeError(f"build did not produce {artifact}")
                except subprocess.CalledProcessError as error:
                    build_error = error
            built = True
        executable = shutil.which(command_line[0])
        if artifact.is_file():
            record = {
                "schema_version": EVIDENCE_SCHEMA_VERSION,
                "key": key,
                **fields,
                "command": list(command_line),
                "cwd": str(cwd),
                "env_digest": environment_digest(os.environ.copy()),
                "executable": artifact_record(Path(executable), self.repo or cwd) if executable else None,
                "artifact": artifact_record(artifact, self.repo or cwd),
                "created_at": time.time(),
                "reused": not built,
                "status": "failed" if build_error else "passed",
                "classification": "build",
            }
            if artifact.is_file():
                record["sha256"] = sha256(artifact)
            temporary = marker.with_name(
                f".{marker.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp"
            )
            temporary.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            try:
                temporary.replace(marker)
            finally:
                temporary.unlink(missing_ok=True)
        if build_error is not None:
            raise build_error
        return {
            "key": key,
            "reused": not built,
            "target": fields["target"],
            "profile": fields["profile"],
            "artifact": artifact_record(artifact, self.repo or cwd),
        }


class Task:
    __slots__ = ("name", "command", "depends_on", "stage", "allow_failure")

    def __init__(
        self,
        name: str,
        command_line: Command,
        depends_on: tuple[str, ...] = (),
        stage: str = "verify",
        allow_failure: bool = False,
    ) -> None:
        self.name = name
        self.command = command_line
        self.depends_on = depends_on
        self.stage = stage
        self.allow_failure = allow_failure


def task(name: str, *argv: str, depends_on: Iterable[str] = (), stage: str = "verify") -> Task:
    return Task(name, command(*argv), tuple(depends_on), stage)


def task_graph(mode: str, tier_only: bool = False) -> tuple[Task, ...]:
    if mode not in {"fast", "verify", "compat", "release"}:
        raise ValueError(f"unknown verification mode: {mode}")
    fast = (
        task("format", "moon", "fmt", "--check", stage="fast"),
        task("architecture", "./tools/verification/checks/architecture.sh", stage="fast"),
        task("check", "moon", "check", "--target", "all", "--warn-list", "+73", stage="fast"),
        task("python-tools", sys.executable, "tools/runner.py", "test-tools", stage="fast"),
    )
    if mode == "fast":
        result = fast
        return result
    verify = fast + (
        task("native-tests", "./tools/verification/checks/test_target.sh", "native", depends_on=("check",)),
        task("wasm-tests", "./tools/verification/checks/test_target.sh", "wasm", depends_on=("check",)),
        task("snapshot", "./tools/upstream/verify_snapshot.sh", depends_on=("check",)),
        task("differential-self-test", "./tools/differential/self_test.sh", depends_on=("check",)),
        task("differential-smoke", "./tools/differential/real_smoke.sh", depends_on=("snapshot",)),
        task(
            "evaluator-oracle",
            sys.executable,
            "tools/upstream/evaluator_oracle.py",
            "--upstream",
            "./_build/upstream/just-1.57.0/target/release/just",
            depends_on=("differential-smoke",),
        ),
        task("async-spike", "./tools/spikes/check_host_async.sh", depends_on=("check",)),
        task("ecosystem-spike", "./tools/spikes/check_ecosystem.sh", depends_on=("check",)),
        task("moon-info", "moon", "info", depends_on=("check",)),
        task("interface-diff", "git", "diff", "--exit-code", depends_on=("moon-info",)),
        task(
            "native-version",
            "./_build/native/debug/build/cmd/just/just.exe",
            "--version",
            depends_on=("native-tests",),
        ),
        task(
            "wasm-version",
            "moonrun",
            "--policy",
            "./policies/execute.toml",
            "./_build/wasm/debug/build/cmd/just/just.wasm",
            "--version",
            depends_on=("wasm-tests",),
        ),
    )
    if mode == "verify":
        result = verify
        return tuple(item for item in result if item.stage == mode) if tier_only else result
    compat = verify + (
        task("compatibility", "./tools/verification/checks/compatibility.sh", depends_on=("native-tests", "wasm-tests"), stage="compat"),
        task("platform", "./tools/verification/checks/platform.sh", depends_on=("native-tests",), stage="compat"),
        task("query", "./tools/verification/checks/query.sh", depends_on=("native-tests", "wasm-tests"), stage="compat"),
        task("hostfs", "./tools/verification/checks/hostfs.sh", depends_on=("wasm-tests",), stage="compat"),
        task("dotenv", "./tools/verification/checks/dotenv.sh", depends_on=("native-tests",), stage="compat"),
        task("invocation", "./tools/verification/checks/invocation.sh", depends_on=("native-tests",), stage="compat"),
        task("workdir", "./tools/verification/checks/workdir.sh", depends_on=("native-tests", "wasm-tests"), stage="compat"),
        task("environment", "./tools/verification/checks/environment.sh", depends_on=("native-tests",), stage="compat"),
        task("executor", "./tools/verification/checks/executor.sh", depends_on=("native-tests",), stage="compat"),
        task("runtime", "./tools/verification/checks/runtime.sh", depends_on=("native-tests", "wasm-tests"), stage="compat"),
        task("inspect", "./tools/verification/checks/inspect.sh", depends_on=("wasm-tests",), stage="compat"),
        task(
            "official-harness",
            sys.executable,
            "tools/upstream/run_official_harness.py",
            "--native-candidate",
            os.environ.get("MOONJUST_NATIVE_CANDIDATE", "./_build/native/debug/build/cmd/just/just.exe"),
            "--wasm-candidate",
            os.environ.get("MOONJUST_WASM_CANDIDATE", "./_build/wasm/debug/build/cmd/just/just.wasm"),
            depends_on=("native-tests", "wasm-tests"),
            stage="compat",
        ),
    )
    if mode == "compat":
        result = compat
        return tuple(item for item in result if item.stage == mode) if tier_only else result
    result = compat + (
        task("contracts", sys.executable, "tools/upstream/run_contract_harness.py", depends_on=("compatibility",), stage="release"),
        task("release", "./tools/verification/checks/release.sh", depends_on=("compatibility", "platform"), stage="release"),
        task("performance", sys.executable, "tools/runner.py", "measure", "--workload", "all", depends_on=("release",), stage="release"),
    )
    return tuple(item for item in result if item.stage == mode) if tier_only else result


def mode_commands(mode: str) -> tuple[Command, ...]:
    """Compatibility helper returning the deterministic task command list."""
    return tuple(item.command for item in task_graph(mode))


def _base_build_fields(repo: Path) -> dict[str, object]:
    source = source_identity(repo)
    moon, moon_digest = toolchain(repo)
    dependencies, dependency_records = dependency_fingerprint(repo)
    source_records = [
        {"path": path.relative_to(repo).as_posix(), "sha256": sha256(path)}
        for path in sorted(repo.rglob("*.mbt"))
        if ".mooncakes" not in path.parts and "_build" not in path.parts
    ]
    source_digest = sha256_bytes(canonical(source_records))
    return {
        **source,
        "moon_toolchain_digest": moon_digest,
        "moon_toolchain": moon,
        "dependency_graph_digest": dependencies,
        "dependency_graph": dependency_records,
        "source_input_digest": source_digest,
        "source_inputs": source_records,
    }


def _build_fields(
    repo: Path,
    target: str,
    profile: str,
    flags: str = "",
    base: dict[str, object] | None = None,
) -> dict[str, object]:
    return {
        **(base or _base_build_fields(repo)),
        "target": target,
        "host_triple": f"{platform.system().lower()}-{platform.machine().lower()}",
        "profile": profile,
        "compiler_flags": flags,
    }


def build_spec(repo: Path, target: str, profile: str) -> tuple[Command, Path, str]:
    moon_target = "wasm" if target == "wasm1" else target
    if target not in {"native", "wasm1"}:
        raise ValueError(f"unsupported target: {target}")
    if profile not in {"debug", "release", "coverage"}:
        raise ValueError(f"unsupported profile: {profile}")
    profile_args: tuple[str, ...]
    target_dir: Path | None = None
    if profile == "debug":
        profile_args = ()
    elif profile == "release":
        profile_args = ("--frozen", "--release", "--strip")
    else:
        target_dir = repo / "_build" / "coverage-build"
        profile_args = ("--enable-coverage", "--target-dir", str(target_dir))
    command_line = ("moon", "build", *profile_args, "--target", moon_target, "cmd/just")
    build_root = target_dir or repo / "_build"
    moon_profile = "release" if profile == "release" else "debug"
    extension = "just.wasm" if target == "wasm1" else "just.exe"
    artifact = build_root / moon_target / moon_profile / "build/cmd/just" / extension
    flags = " ".join(profile_args)
    return command_line, artifact, flags


def ensure_build(
    repo: Path,
    target: str,
    profile: str,
    execute: bool = True,
    base: dict[str, object] | None = None,
) -> dict[str, object]:
    command_line, artifact, flags = build_spec(repo, target, profile)
    registry = BuildRegistry(repo / "_build" / "verification" / "registry", repo)
    fields = _build_fields(repo, target, profile, flags, base)
    return registry.ensure(fields, command_line, artifact, repo, execute=execute)


def prepare_builds(repo: Path, execute: bool = True) -> tuple[dict[str, str], list[dict[str, object]]]:
    registry = BuildRegistry(repo / "_build" / "verification" / "registry", repo)
    base = _base_build_fields(repo)
    builds: list[dict[str, object]] = []
    oracle = repo / "_build/upstream/just-1.57.0/target/release/just"
    native = repo / "_build/native/debug/build/cmd/just/just.exe"
    wasm = repo / "_build/wasm/debug/build/cmd/just/just.wasm"
    specs = (
        ("official", "release", ("./tools/upstream/build_oracle.sh",), oracle, "official"),
        ("native", "debug", ("moon", "build", "--target", "native", "cmd/just"), native, "native"),
        ("wasm1", "debug", ("moon", "build", "--target", "wasm", "cmd/just"), wasm, "wasm"),
    )
    for target, profile, argv, artifact, key_target in specs:
        fields = _build_fields(repo, key_target, profile, base=base)
        builds.append(registry.ensure(fields, argv, artifact, repo, execute=execute))
    return {
        "MOONJUST_ORACLE_CANDIDATE": str(oracle),
        "MOONJUST_NATIVE_CANDIDATE": str(native),
        "MOONJUST_WASM_CANDIDATE": str(wasm),
    }, builds


def prepare_measurement_builds(repo: Path, execute: bool = True) -> list[dict[str, object]]:
    """Build the exact release comparison set through the provenance registry."""
    registry = BuildRegistry(repo / "_build" / "verification" / "registry", repo)
    base = _base_build_fields(repo)
    official = repo / "_build/upstream/just-1.57.0/target/release/just"
    official_fields = _build_fields(repo, "official", "release", base=base)
    builds = [
        registry.ensure(
            official_fields,
            ("./tools/upstream/build_oracle.sh",),
            official,
            repo,
            execute=execute,
        )
    ]
    builds.append(ensure_build(repo, "native", "release", execute=execute, base=base))
    builds.append(ensure_build(repo, "wasm1", "release", execute=execute, base=base))
    return builds


def run_task(task_item: Task, repo: Path, env: dict[str, str]) -> dict[str, object]:
    started = time.perf_counter_ns()
    argv = executable_command(task_item.command)
    result = subprocess.run(
        argv,
        cwd=repo,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    stdout = result.stdout.encode("utf-8")
    stderr = result.stderr.encode("utf-8")
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    return {
        "name": task_item.name,
        "stage": task_item.stage,
        "command": {
            "argv": relative_command(repo, argv),
            "cwd": ".",
            "env_digest": environment_digest(env),
        },
        "started_at_ns": started,
        "duration_ms": (time.perf_counter_ns() - started) / 1_000_000,
        "exit_code": result.returncode,
        "status": "passed" if result.returncode == 0 else "failed",
        "classification": "correctness" if result.returncode else "ok",
        "stdout_sha256": sha256_bytes(stdout),
        "stderr_sha256": sha256_bytes(stderr),
        "stdout_tail": result.stdout[-4000:],
        "stderr_tail": result.stderr[-4000:],
    }


def evidence_record(
    repo: Path,
    mode: str,
    baseline_sha: str | None,
    tasks: list[dict[str, object]],
    builds: list[dict[str, object]],
    started_at: float,
) -> dict[str, object]:
    source = source_identity(repo)
    moon, moon_digest = toolchain(repo)
    dep_digest, dependencies = dependency_fingerprint(repo)
    nonzero_exit = next(
        (
            int(item["exit_code"])
            for item in tasks
            if isinstance(item.get("exit_code"), int) and item["exit_code"] != 0
        ),
        0,
    )
    return {
        "schema_version": EVIDENCE_SCHEMA_VERSION,
        "runner_version": RUNNER_VERSION,
        "run_id": f"{source['commit_sha'][:12]}-{uuid.uuid4().hex[:12]}",
        "stage": mode,
        "mode": mode,
        "commit_sha": source["commit_sha"],
        "tree_sha": source["tree_sha"],
        "baseline_sha": baseline_sha,
        "host": host_identity(),
        "target": "all",
        "profile": "debug" if mode != "release" else "release",
        "command": {
            "argv": ["python3", "tools/runner.py", "run", "--mode", mode],
            "cwd": ".",
            "env_digest": environment_digest(os.environ.copy()),
        },
        "toolchain": {"value": moon, "digest": moon_digest},
        "dependencies": {"digest": dep_digest, "manifests": dependencies},
        "registry_refs": builds,
        "artifact_hashes": {
            str(item.get("artifact", {}).get("relative_path")): item.get("artifact", {}).get("sha256")
            for item in builds
            if isinstance(item.get("artifact"), dict)
        },
        "started_at": started_at,
        "duration_ms": sum(float(item["duration_ms"]) for item in tasks),
        "exit_code": nonzero_exit,
        "status": (
            "planned"
            if tasks and all(item["status"] == "planned" for item in tasks)
            else "passed"
            if all(item["status"] == "passed" for item in tasks)
            else "failed"
        ),
        "classification": "correctness",
        "measurements": {"tasks": tasks},
    }


def validate_evidence(path: Path, expected_sha: str | None = None) -> None:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("evidence root must be an object")
    required = {
        "schema_version", "run_id", "stage", "mode", "commit_sha", "tree_sha",
        "baseline_sha", "host", "target", "profile", "toolchain", "dependencies",
        "registry_refs", "artifact_hashes", "started_at", "duration_ms", "exit_code",
        "status", "classification", "measurements",
    }
    missing = sorted(required - set(value))
    if missing:
        raise ValueError("evidence is missing required fields: " + ", ".join(missing))
    if value["schema_version"] != EVIDENCE_SCHEMA_VERSION:
        raise ValueError(f"unsupported evidence schema: {value['schema_version']!r}")
    commit = value["commit_sha"]
    if not isinstance(commit, str) or len(commit) != 40:
        raise ValueError("evidence commit_sha is not a full SHA-1")
    if expected_sha and commit != expected_sha:
        raise ValueError(f"evidence commit_sha {commit} differs from expected head {expected_sha}")
    if value["status"] not in {"planned", "passed", "failed", "infrastructure-invalid"}:
        raise ValueError("evidence status is invalid")
    if not isinstance(value.get("command"), dict) or not value["command"].get("argv"):
        raise ValueError("evidence command argv is empty")
    measurements = value["measurements"]
    if not isinstance(measurements, dict):
        raise ValueError("evidence measurements must be an object")
    tasks = measurements.get("tasks")
    if tasks is not None:
        if not isinstance(tasks, list):
            raise ValueError("evidence measurements.tasks must be an array")
        for row in tasks:
            if not isinstance(row, dict) or not isinstance(row.get("command"), dict):
                raise ValueError("each task must contain a command object")
            if row["command"].get("argv") in (None, []):
                raise ValueError("task command argv is empty")


def run(
    mode: str,
    repo: Path,
    dry_run: bool = False,
    evidence: Path | None = None,
    expected_sha_value: str | None = None,
    tier_only: bool = False,
    selected_tasks: set[str] | None = None,
    prepare: bool = True,
) -> int:
    identity = source_identity(repo)
    expected = expected_commit(expected_sha_value)
    if expected and identity["commit_sha"] != expected:
        raise RuntimeError(f"checked out commit {identity['commit_sha']} differs from exact head {expected}")
    env = os.environ.copy()
    builds: list[dict[str, object]] = []
    if prepare and mode in {"verify", "compat", "release"}:
        prepared, builds = prepare_builds(repo, execute=not dry_run)
        env.update(prepared)
        env["MOONJUST_REUSE_BUILD"] = "1"
        if mode == "release":
            builds.extend(prepare_measurement_builds(repo, execute=not dry_run))
    tasks: list[dict[str, object]] = []
    completed: set[str] = set()
    task_status: dict[str, str] = {}
    failures = False
    started_at = time.time()
    graph = task_graph(mode, tier_only=tier_only)
    if selected_tasks is not None:
        unknown = sorted(selected_tasks - {item.name for item in graph})
        if unknown:
            raise ValueError("unknown selected tasks: " + ", ".join(unknown))
        graph = tuple(item for item in graph if item.name in selected_tasks)
    graph_names = {item.name for item in graph}
    for item in graph:
        required_here = set(item.depends_on) & graph_names
        if not required_here.issubset(completed):
            raise RuntimeError(f"task graph order is invalid for {item.name}")
        if failures and mode in {"fast", "verify"}:
            break
        blocked_by = sorted(
            dependency
            for dependency in item.depends_on
            if task_status.get(dependency) in {"failed", "dependency-blocked"}
        )
        if blocked_by:
            record = {
                "name": item.name,
                "stage": item.stage,
                "command": {
                    "argv": relative_command(repo, item.command),
                    "cwd": ".",
                    "env_digest": environment_digest(env),
                },
                "started_at_ns": time.perf_counter_ns(),
                "duration_ms": 0.0,
                "exit_code": None,
                "status": "dependency-blocked",
                "classification": "dependency-blocked",
                "blocked_by": blocked_by,
            }
            tasks.append(record)
            task_status[item.name] = "dependency-blocked"
            completed.add(item.name)
            continue
        print(f"==> {item.name}: {' '.join(item.command)}", flush=True)
        if dry_run:
            record = {
                "name": item.name,
                "stage": item.stage,
                "command": {"argv": relative_command(repo, item.command), "cwd": ".", "env_digest": environment_digest(env)},
                "started_at_ns": time.perf_counter_ns(),
                "duration_ms": 0.0,
                "exit_code": 0,
                "status": "planned",
                "classification": "dry-run",
                "stdout_sha256": sha256_bytes(b""),
                "stderr_sha256": sha256_bytes(b""),
            }
        else:
            record = run_task(item, repo, env)
        tasks.append(record)
        completed.add(item.name)
        task_status[item.name] = str(record["status"])
        failures = failures or record["status"] == "failed"
    output = evidence or repo / "_build" / "verification" / f"{mode}.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    record = evidence_record(repo, mode, os.environ.get("MOONJUST_BASELINE_SHA"), tasks, builds, started_at)
    output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    validate_evidence(output, identity["commit_sha"])
    return 1 if failures else 0


def run_measurement(
    repo: Path,
    workload: str,
    output: Path | None = None,
    authoritative: bool = False,
    baseline_native: Path | None = None,
    baseline_wasm: Path | None = None,
    report_only: bool = False,
) -> int:
    """Run the existing statistically strict sampler through the unified CLI."""
    started_at = time.time()
    builds = prepare_measurement_builds(repo)
    native = repo / "_build/native/release/build/cmd/just/just.exe"
    wasm = repo / "_build/wasm/release/build/cmd/just/just.wasm"
    official = repo / "_build/upstream/just-1.57.0/target/release/just"
    policy = repo / "policies/execute.toml"
    if not all(path.is_file() for path in (native, wasm, official, policy)):
        raise RuntimeError("release measurement requires official, Native, Wasm, and policy artifacts")
    output = output or repo / "_build/performance/results.json"
    raw_report = output.with_suffix(".raw.json")
    command_line = [
        sys.executable, "tools/performance/benchmark.py",
        "--official", str(official), "--native", str(native), "--wasm", str(wasm),
        "--policy", str(policy), "--output", str(raw_report), "--raw-output", str(output.with_suffix(".jsonl")),
    ]
    if authoritative:
        command_line.append("--authoritative")
    if report_only:
        command_line.append("--report-only")
    if baseline_native is not None or baseline_wasm is not None:
        if baseline_native is None or baseline_wasm is None:
            raise ValueError("both baseline_native and baseline_wasm are required")
        command_line += ["--baseline-native", str(baseline_native), "--baseline-wasm", str(baseline_wasm)]
    if workload not in {"all", ""}:
        command_line += ["--workload", workload]
    result = subprocess.run(command_line, cwd=repo, check=False)
    if not raw_report.is_file():
        return result.returncode
    report = json.loads(raw_report.read_text(encoding="utf-8"))
    source = source_identity(repo)
    moon, moon_digest = toolchain(repo)
    dependencies, manifests = dependency_fingerprint(repo)
    command_record = {
        "argv": relative_command(repo, tuple(command_line)),
        "cwd": ".",
        "env_digest": environment_digest(os.environ.copy()),
    }
    evidence = {
        "schema_version": EVIDENCE_SCHEMA_VERSION,
        "runner_version": RUNNER_VERSION,
        "run_id": f"{source['commit_sha'][:12]}-{uuid.uuid4().hex[:12]}",
        "stage": "release" if authoritative else "measure",
        "mode": "measure",
        "commit_sha": source["commit_sha"],
        "tree_sha": source["tree_sha"],
        "baseline_sha": os.environ.get("MOONJUST_BASELINE_SHA"),
        "host": host_identity(),
        "target": "all",
        "profile": "release",
        "command": command_record,
        "toolchain": {"value": moon, "digest": moon_digest},
        "dependencies": {"digest": dependencies, "manifests": manifests},
        "registry_refs": builds,
        "artifact_hashes": {
            str(item.get("artifact", {}).get("relative_path")): item.get("artifact", {}).get("sha256")
            for item in builds
            if isinstance(item.get("artifact"), dict)
        },
        "started_at": started_at,
        "duration_ms": (time.time() - started_at) * 1000,
        "exit_code": result.returncode,
        "status": report.get("status", "failed") if isinstance(report, dict) else "failed",
        "classification": "performance",
        "measurements": {"report": report, "raw_samples": str(output.with_suffix(".jsonl"))},
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    validate_evidence(output, source["commit_sha"])
    return result.returncode


def run_coverage(repo: Path, target: str, base: str | None = None) -> int:
    if target not in {"native", "wasm", "merge"}:
        raise ValueError("coverage target must be native, wasm, or merge")
    if target == "merge":
        command_line = (
            sys.executable,
            "tools/quality/merge_coverage.py",
            "_build/coverage/native.raw.xml",
            "_build/coverage/wasm.raw.xml",
            "--repo",
            str(repo),
            "--cobertura",
            "_build/coverage/cobertura.xml",
            "--summary",
            "_build/coverage/summary.json",
            "--baseline",
            "compat/coverage-baseline.json",
        )
        if base:
            command_line += ("--base", base)
    else:
        command_line = (
            sys.executable,
            "tools/verification/checks/coverage_target.sh",
            target,
        )
    # coverage_target.sh is executable shell despite its .sh suffix; invoke it
    # through the platform shell to keep Windows Git Bash behavior explicit.
    if target != "merge":
        command_line = ("sh", *command_line[1:])
    return subprocess.run(command_line, cwd=repo, check=False).returncode


def test_tools(repo: Path) -> int:
    tests = sorted(
        path
        for path in (repo / "tools").rglob("*_test.py")
        if ".mooncakes" not in path.parts and "_build" not in path.parts
    )
    for path in tests:
        subprocess.run([sys.executable, str(path)], cwd=repo, check=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--expected-sha")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--mode", choices=("fast", "verify", "compat", "release"), required=True)
    run_parser.add_argument("--dry-run", action="store_true")
    run_parser.add_argument("--evidence", type=Path)
    run_parser.add_argument("--tier-only", action="store_true")
    run_parser.add_argument("--task", action="append", default=[])
    run_parser.add_argument("--no-build", action="store_true")

    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("--target", choices=("native", "wasm1"), required=True)
    build_parser.add_argument("--profile", choices=("debug", "release", "coverage"), required=True)
    build_parser.add_argument("--dry-run", action="store_true")

    measure_parser = subparsers.add_parser("measure")
    measure_parser.add_argument("--workload", default="all")
    measure_parser.add_argument("--output", type=Path)
    measure_parser.add_argument("--authoritative", action="store_true")
    measure_parser.add_argument("--baseline-native", type=Path)
    measure_parser.add_argument("--baseline-wasm", type=Path)
    measure_parser.add_argument("--report-only", action="store_true")

    coverage_parser = subparsers.add_parser("coverage")
    coverage_parser.add_argument("--target", choices=("native", "wasm", "merge"), required=True)
    coverage_parser.add_argument("--base")

    evidence_parser = subparsers.add_parser("evidence")
    evidence_sub = evidence_parser.add_subparsers(dest="evidence_command", required=True)
    validate_parser = evidence_sub.add_parser("validate")
    validate_parser.add_argument("path", type=Path)
    registry_parser = subparsers.add_parser("registry")
    registry_sub = registry_parser.add_subparsers(dest="registry_command", required=True)
    registry_sub.add_parser("inspect")
    registry_sub.add_parser("gc")
    subparsers.add_parser("test-tools")

    args = parser.parse_args()
    repo = args.repo.resolve()
    expected = args.expected_sha
    if args.subcommand == "run":
        return run(
            args.mode,
            repo,
            args.dry_run,
            args.evidence.resolve() if args.evidence else None,
            expected,
            args.tier_only,
            set(args.task) if args.task else None,
            not args.no_build,
        )
    if args.subcommand == "build":
        if args.profile == "coverage":
            coverage_target = "wasm" if args.target == "wasm1" else args.target
            if args.dry_run:
                print(json.dumps({"target": coverage_target, "profile": "coverage"}, sort_keys=True))
                return 0
            return run_coverage(repo, coverage_target)
        record = ensure_build(repo, args.target, args.profile, execute=not args.dry_run)
        print(json.dumps(record, indent=2, sort_keys=True))
        return 0
    if args.subcommand == "measure":
        return run_measurement(
            repo,
            args.workload,
            args.output.resolve() if args.output else None,
            args.authoritative,
            args.baseline_native.resolve() if args.baseline_native else None,
            args.baseline_wasm.resolve() if args.baseline_wasm else None,
            args.report_only,
        )
    if args.subcommand == "coverage":
        return run_coverage(repo, args.target, args.base)
    if args.subcommand == "evidence":
        validate_evidence(args.path.resolve(), expected)
        print(f"evidence valid: {args.path}")
        return 0
    if args.subcommand == "registry":
        registry = BuildRegistry(repo / "_build" / "verification" / "registry", repo)
        if args.registry_command == "inspect":
            print(json.dumps(registry.inspect(), indent=2, sort_keys=True))
        else:
            print(f"removed {registry.gc()} temporary registry records")
        return 0
    return test_tools(repo)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.CalledProcessError, subprocess.SubprocessError, RuntimeError, ValueError) as error:
        print(f"moonjust runner error: {error}", file=sys.stderr)
        raise SystemExit(1)
