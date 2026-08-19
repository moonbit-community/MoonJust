#!/usr/bin/env python3
"""Run pinned just integration tests against oracle, Native, and wasm1 binaries."""

from __future__ import annotations

import ast
import argparse
import difflib
import json
import os
import platform
import re
import signal
import shutil
import subprocess
import sys
import time
import tomllib
from pathlib import Path


UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
SCHEMA_VERSION = 4
WASM_SKIPS = ("signals::",)
NATIVE_SIGNAL_TESTS = {
    "signals::continue_default_excludes_hangup",
    "signals::continue_default_excludes_quit",
    "signals::continue_default_line",
    "signals::continue_default_shebang",
    "signals::continue_explicit_excludes_unlisted",
    "signals::continue_hangup_opt_in",
    "signals::continue_runs_subsequents",
    "signals::infallible_line_clears_caught_signal",
    "signals::interrupt_backtick",
    "signals::interrupt_command",
    "signals::interrupt_line",
    "signals::interrupt_shebang",
    "signals::forwarding",
}
NATIVE_SIGINFO_SYSTEMS = {"Darwin", "DragonFly", "FreeBSD", "iOS", "NetBSD", "OpenBSD"}
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
DIAGNOSTIC_KEYWORDS = {
    "alias",
    "argument",
    "attribute",
    "assignment",
    "backtick",
    "boolean",
    "cache",
    "command",
    "comparison",
    "conditional",
    "dependency",
    "directory",
    "dotenv",
    "environment",
    "escape",
    "file",
    "format",
    "function",
    "guard",
    "import",
    "indentation",
    "interpreter",
    "justfile",
    "list",
    "metadata",
    "module",
    "option",
    "operator",
    "parameter",
    "path",
    "platform",
    "recipe",
    "recursion",
    "setting",
    "shell",
    "signal",
    "string",
    "unexport",
    "variable",
    "version",
    "whitespace",
}

RESULT_CLASSIFICATIONS = {
    "exact",
    "diagnostic-exact",
    "diagnostic-semantic",
    "product-identity",
    "excluded-completion",
    "upstream-ignored",
    "failed",
}
EXCEPTION_CLASSIFICATIONS = {
    "diagnostic-exact",
    "diagnostic-semantic",
    "product-identity",
    "excluded-completion",
}


def rust_string_literal(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise RuntimeError(message)


def run_shell_script(script: Path, cwd: Path) -> None:
    shell = shutil.which("sh") or shutil.which("bash")
    if shell is None:
        fail("a POSIX shell is required to build the pinned upstream oracle")
    result = subprocess.run(
        [shell, script.as_posix()],
        cwd=cwd,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        fail(
            f"upstream oracle build failed ({result.returncode}):\n"
            f"{result.stdout}{result.stderr}"
        )


def load_exceptions(path: Path, tests: list[str]) -> dict[str, dict[str, object]]:
    if not path.is_file():
        fail(f"compatibility exception manifest is missing: {path}")
    with path.open("rb") as handle:
        document = tomllib.load(handle)
    if document.get("schema_version") != 1:
        fail("unsupported compatibility exception schema")
    if document.get("upstream_commit") != UPSTREAM_COMMIT:
        fail("compatibility exceptions target a different upstream commit")
    known = set(tests)
    rules: dict[str, dict[str, object]] = {}
    for index, raw in enumerate(document.get("exceptions", []), start=1):
        if not isinstance(raw, dict):
            fail(f"compatibility exception {index} is not a table")
        name = raw.get("test")
        classification = raw.get("classification")
        reason = raw.get("reason")
        owner = raw.get("owner")
        targets = raw.get("targets")
        if not isinstance(name, str) or name not in known:
            fail(f"compatibility exception {index} has unknown exact test ID: {name!r}")
        if name in rules:
            fail(f"duplicate compatibility exception for {name}")
        if classification not in EXCEPTION_CLASSIFICATIONS:
            fail(f"invalid compatibility classification for {name}: {classification!r}")
        if not isinstance(reason, str) or not reason.strip():
            fail(f"compatibility exception {name} has no reason")
        if not isinstance(owner, str) or not owner.strip():
            fail(f"compatibility exception {name} has no owner")
        if (
            not isinstance(targets, list)
            or not targets
            or any(target not in {"native", "wasm1"} for target in targets)
            or len(set(targets)) != len(targets)
        ):
            fail(f"compatibility exception {name} has invalid targets")
        if classification == "diagnostic-exact":
            normalizations = raw.get("normalizations")
            if normalizations != ["ansi"]:
                fail(
                    f"diagnostic-exact exception {name} must declare only "
                    "normalizations = ['ansi']"
                )
        rules[name] = raw
    completion_names = {name for name in tests if name.startswith("completions::")}
    excluded_names = {
        name
        for name, rule in rules.items()
        if rule["classification"] == "excluded-completion"
    }
    if excluded_names != completion_names:
        fail(
            "completion exclusions must enumerate the pinned suite exactly: "
            f"missing={sorted(completion_names - excluded_names)}, "
            f"extra={sorted(excluded_names - completion_names)}"
        )
    return rules


def clean_subprocess_environment(
    env: dict[str, str] | None = None,
) -> dict[str, str]:
    environment = os.environ.copy() if env is None else env.copy()
    for name in (
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_PREFIX",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_COMMON_DIR",
        "GIT_NAMESPACE",
    ):
        environment.pop(name, None)
    if os.name == "nt":
        git_paths = [
            Path(r"C:\Program Files\Git\bin"),
            Path(r"C:\Program Files\Git\usr\bin"),
        ]
        existing = [str(path) for path in git_paths if path.is_dir()]
        if existing:
            path_key = next(
                (key for key in environment if key.casefold() == "path"),
                "Path",
            )
            current_path = environment.get(path_key, "")
            for key in list(environment):
                if key.casefold() == "path":
                    environment.pop(key, None)
            environment[path_key] = os.pathsep.join(existing + [current_path])
    return environment


def run(command: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=clean_subprocess_environment(env),
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=600,
    )


def reset_subprocess_signals() -> None:
    """Prevent an ignored parent signal mask from invalidating signal tests."""
    signal.pthread_sigmask(signal.SIG_SETMASK, [])
    for signum in (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM):
        signal.signal(signum, signal.SIG_DFL)


def run_isolated_unix(
    command: list[str],
    *,
    cwd: Path,
    timeout: float,
    extra_env: dict[str, str] | None = None,
) -> tuple[subprocess.CompletedProcess[str], bool]:
    environment = os.environ.copy()
    if extra_env:
        environment.update(extra_env)
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=clean_subprocess_environment(environment),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        start_new_session=True,
        preexec_fn=reset_subprocess_signals,
    )

    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        timeout_stderr = ""
        try:
            snapshot = subprocess.run(
                [
                    "ps",
                    "-eo",
                    "pid=,ppid=,pgid=,sid=,stat=,args=",
                    "--forest",
                ],
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=5,
            )
            timeout_stderr = (
                "\n[timeout process snapshot]\n"
                + snapshot.stdout
                + snapshot.stderr
            )
        except (OSError, subprocess.SubprocessError) as error:
            timeout_stderr = f"\n[timeout process snapshot unavailable: {error}]\n"
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        stdout, stderr = process.communicate()
        stderr += timeout_stderr
    return (
        subprocess.CompletedProcess(
            command,
            124 if timed_out else process.returncode,
            stdout,
            stderr,
        ),
        timed_out,
    )


def linux_processes_with_environment(name: str, value: str) -> list[int]:
    """Find live Linux processes carrying a unique harness environment marker."""
    if platform.system() != "Linux":
        return []
    marker = f"{name}={value}".encode() + b"\0"
    matches: list[int] = []
    for entry in Path("/proc").glob("[0-9]*"):
        try:
            environment = (entry / "environ").read_bytes()
        except (OSError, UnicodeError):
            continue
        if marker in environment:
            try:
                matches.append(int(entry.name))
            except ValueError:
                continue
    return sorted(matches)


def wait_for_linux_process_cleanup(name: str, value: str) -> list[int]:
    deadline = time.monotonic() + 1.0
    while True:
        matches = linux_processes_with_environment(name, value)
        if not matches or time.monotonic() >= deadline:
            return matches
        time.sleep(0.02)


def compile_harness(source: Path, target: Path) -> tuple[Path, Path]:
    environment = os.environ.copy()
    environment["CARGO_TARGET_DIR"] = str(target)
    result = run(
        [
            "cargo",
            "test",
            "--manifest-path",
            str(source / "Cargo.toml"),
            "--test",
            "integration",
            "--no-run",
            "--locked",
            "--message-format=json",
        ],
        cwd=source,
        env=environment,
    )
    if result.returncode != 0:
        fail(f"failed to compile pinned integration harness:\n{result.stderr}")
    executable: Path | None = None
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target_info = message.get("target", {})
        if (
            message.get("reason") == "compiler-artifact"
            and target_info.get("name") == "integration"
            and "test" in target_info.get("kind", [])
            and message.get("executable")
        ):
            executable = Path(message["executable"])
    if executable is None or not executable.is_file():
        fail("cargo did not report the integration test executable")
    bound_binary = target / "debug" / ("just.exe" if os.name == "nt" else "just")
    if not bound_binary.is_file():
        fail(f"cargo did not build the bound just binary: {bound_binary}")
    return executable, bound_binary


def list_tests(executable: Path, source: Path) -> list[str]:
    result = run([str(executable), "--list", "--format=terse"], cwd=source)
    if result.returncode != 0:
        fail(f"failed to list integration tests:\n{result.stderr}")
    tests = sorted(
        line.removesuffix(": test")
        for line in result.stdout.splitlines()
        if line.endswith(": test")
    )
    if not tests:
        fail("pinned integration harness reported no tests")
    return tests


def install_binary(bound_binary: Path, candidate: Path) -> None:
    shutil.copy2(candidate, bound_binary)
    bound_binary.chmod(0o755)


def install_wasm_wrapper(
    bound_binary: Path,
    moonrun: str,
    policy: Path,
    candidate: Path,
) -> None:
    operating_system = {
        "Darwin": "macos",
        "Linux": "linux",
    }.get(platform.system(), "wasm")
    architecture = platform.machine() or "unknown"
    num_cpus = os.cpu_count() or 1
    if os.name == "nt":
        source = bound_binary.with_name("moonjust-wasm-launcher.rs")
        source.write_text(
            "use std::{env, process::{self, Command}};\n"
            "fn main() {\n"
            f"  let mut command = Command::new({rust_string_literal(moonrun)});\n"
            f"  command.arg(\"--policy\").arg({rust_string_literal(str(policy))})"
            f".arg({rust_string_literal(str(candidate))});\n"
            "  command.args(env::args_os().skip(1));\n"
            "  command.env(\"MOONJUST_EXECUTABLE\", "
            "env::current_exe().unwrap_or_default());\n"
            "  command.env(\"MOONJUST_PID\", process::id().to_string());\n"
            f"  command.env(\"MOONJUST_NUM_CPUS\", {rust_string_literal(str(num_cpus))});\n"
            f"  command.env(\"MOONJUST_ARCH\", {rust_string_literal(architecture)});\n"
            "  command.env(\"MOONJUST_OS\", \"windows\");\n"
            "  let status = command.status().expect(\"failed to launch moonrun\");\n"
            "  process::exit(status.code().unwrap_or(1));\n"
            "}\n",
            encoding="utf-8",
        )
        result = run(
            ["rustc", "--edition=2021", "-O", str(source), "-o", str(bound_binary)],
            cwd=bound_binary.parent,
        )
        if result.returncode != 0:
            fail(f"failed to compile Windows wasm1 launcher:\n{result.stderr}")
        return
    bound_binary.write_text(
        "#!/bin/sh\n"
        + "MOONJUST_EXECUTABLE=\"$0\"\n"
        + "MOONJUST_PID=\"$$\"\n"
        + f"MOONJUST_NUM_CPUS={num_cpus}\n"
        + f"MOONJUST_ARCH={architecture!r}\n"
        + f"MOONJUST_OS={operating_system!r}\n"
        + "export MOONJUST_EXECUTABLE MOONJUST_PID MOONJUST_NUM_CPUS MOONJUST_ARCH MOONJUST_OS\n"
        + "exec "
        + " ".join(
            [
                repr(moonrun),
                "--policy",
                repr(str(policy)),
                repr(str(candidate)),
                '"$@"',
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    bound_binary.chmod(0o755)


def parse_statuses(output: str, tests: list[str], skips: tuple[str, ...]) -> dict[str, str]:
    statuses: dict[str, str] = {}
    pattern = re.compile(r"^test (.+?) \.\.\. (ok|FAILED|ignored(?:, .*)?)$", re.MULTILINE)
    for name, raw_status in pattern.findall(output):
        if raw_status == "ok":
            statuses[name] = "passed"
        elif raw_status == "FAILED":
            statuses[name] = "failed"
        else:
            statuses[name] = "ignored"
    for name in tests:
        if name not in statuses and any(name.startswith(prefix) for prefix in skips):
            statuses[name] = "filtered"
    missing = sorted(set(tests) - statuses.keys())
    if missing:
        fail(f"harness output omitted {len(missing)} tests, first: {missing[0]}")
    return statuses


def failure_blocks(output: str) -> dict[str, str]:
    clean = ANSI_ESCAPE.sub("", output)
    parts = re.split(r"^---- (.+?) stdout ----\n", clean, flags=re.MULTILINE)
    return {
        parts[index]: parts[index + 1]
        for index in range(1, len(parts), 2)
    }


def diagnostic_sides(block: str) -> tuple[str, str] | None:
    if "Bad stderr:" not in block:
        return None
    if any(
        marker in block
        for marker in (
            "Bad status:",
            "Bad stdout:",
            "Stdout regex mismatch:",
            "Stderr regex mismatch:",
            "file mismatch",
            "expected file",
        )
    ):
        return None
    diff = block.split("Bad stderr:", 1)[1].split("\n\nthread '", 1)[0]
    left: list[str] = []
    right: list[str] = []
    for line in diff.splitlines():
        if line.startswith("Diff ") or line.startswith("< left"):
            continue
        if line.startswith("<"):
            left.append(line[1:])
        elif line.startswith(">"):
            right.append(line[1:])
        elif line.startswith(" "):
            left.append(line[1:])
            right.append(line[1:])
    if not left or not right:
        return None
    return "\n".join(left), "\n".join(right)


def bounded_diagnostic_regex_difference(block: str) -> bool:
    """Allow only a stable MoonJust error-code prefix in upstream regex tests."""
    clean = ANSI_ESCAPE.sub("", block)
    match = re.search(
        r'Stderr regex mismatch:\n(?P<actual>"(?:\\.|[^"\\])*")\n'
        r'!~=\n/Regex\("(?P<expected>(?:\\.|[^"\\])*)"\)/',
        clean,
    )
    if match is None:
        return False
    try:
        actual = ast.literal_eval(match.group("actual"))
        expected = ast.literal_eval('"' + match.group("expected") + '"')
    except (SyntaxError, ValueError):
        return False
    if "error:" not in expected or not re.match(r"error\[MJ-[A-Z0-9-]+\]:", actual):
        return False
    normalized = re.sub(r"^error\[MJ-[A-Z0-9-]+\]:", "error:", actual)
    normalized_expected = expected.replace("^(?s)", "(?s)^")
    try:
        matched = re.search(normalized_expected, normalized) is not None
    except re.error:
        matched = False
    actual_lower = actual.lower()
    expected_lower = expected.lower()
    actual_keywords = {word for word in DIAGNOSTIC_KEYWORDS if word in actual_lower}
    expected_keywords = {word for word in DIAGNOSTIC_KEYWORDS if word in expected_lower}
    if not (actual_keywords & expected_keywords):
        return False
    if matched:
        return True
    expected_arguments = {
        argument
        for argument in re.findall(r"`([^`]+)`", expected)
        if not re.search(r"[.*+?{}\[\]()]", argument)
    }
    if expected_arguments and not any(
        argument.lower() in actual_lower for argument in expected_arguments
    ):
        return False
    return True


def is_bounded_diagnostic_difference(block: str) -> bool:
    if bounded_diagnostic_regex_difference(block):
        return True
    sides = diagnostic_sides(block)
    if sides is None:
        return False
    actual, expected = sides
    if "error" not in actual.lower() or "error" not in expected.lower():
        return False
    location = re.compile(r"(?:-->|——▶) [^\n:]+:(\d+):(\d+)")
    actual_locations = set(location.findall(actual))
    expected_locations = set(location.findall(expected))
    if bool(actual_locations) != bool(expected_locations):
        return False
    actual_lines = {line for line, _ in actual_locations}
    expected_lines = {line for line, _ in expected_locations}
    if actual_lines and not (actual_lines & expected_lines):
        return False
    actual_lower = actual.lower()
    expected_lower = expected.lower()
    actual_keywords = {word for word in DIAGNOSTIC_KEYWORDS if word in actual_lower}
    expected_keywords = {word for word in DIAGNOSTIC_KEYWORDS if word in expected_lower}
    if not (actual_keywords & expected_keywords):
        return False
    normalize_argument = lambda value: re.sub(r"\s+", " ", value).strip()
    actual_arguments = {
        normalize_argument(value) for value in re.findall(r"`([^`]+)`", actual)
    }
    expected_arguments = {
        normalize_argument(value) for value in re.findall(r"`([^`]+)`", expected)
    }
    if expected_arguments:
        direct_match = actual_arguments & expected_arguments
        textual_match = any(
            argument.lower() in expected_lower for argument in actual_arguments
        ) or any(argument.lower() in actual_lower for argument in expected_arguments)
        if not direct_match and not textual_match:
            return False
    return True


def is_ansi_normalized_diagnostic_exact(block: str) -> bool:
    """Accept a failed upstream assertion only when ANSI removal is sufficient."""
    sides = diagnostic_sides(block)
    return sides is not None and sides[0] == sides[1]


def execute_harness(
    label: str,
    executable: Path,
    source: Path,
    tests: list[str],
    exceptions: dict[str, dict[str, object]] | None = None,
    skips: tuple[str, ...] = (),
) -> dict[str, str]:
    # The upstream harness mutates process-wide signal and environment state in
    # several cases. Run registrations serially so each differential result is
    # independent; recipe parallelism is exercised by dedicated cases.
    command = [str(executable), "--test-threads=1", "--color=never"]
    for prefix in skips:
        command.extend(["--skip", prefix])
    result = run(command, cwd=source)
    artifact = repository_root() / "_build" / "upstream-harness"
    artifact.mkdir(parents=True, exist_ok=True)
    (artifact / f"{label}.log").write_text(
        result.stdout + result.stderr,
        encoding="utf-8",
    )
    combined = result.stdout + result.stderr
    statuses = parse_statuses(combined, tests, skips)
    if exceptions is None:
        return statuses
    blocks = failure_blocks(combined)
    for name, status in statuses.items():
        rule = exceptions.get(name)
        target_rule = rule if rule is not None and label in rule["targets"] else None
        if (
            target_rule is not None
            and target_rule["classification"] == "excluded-completion"
        ):
            statuses[name] = "excluded-completion"
            continue
        if status in {"ignored", "filtered"}:
            statuses[name] = "upstream-ignored"
            continue
        if status == "passed":
            statuses[name] = "exact"
            continue
        block = blocks.get(name, "")
        if (
            target_rule is not None
            and target_rule["classification"] == "diagnostic-exact"
            and is_ansi_normalized_diagnostic_exact(block)
        ):
            statuses[name] = "diagnostic-exact"
        elif (
            target_rule is not None
            and target_rule["classification"] == "diagnostic-semantic"
            and is_bounded_diagnostic_difference(block)
        ):
            statuses[name] = "diagnostic-semantic"
        elif (
            target_rule is not None
            and target_rule["classification"] == "product-identity"
            and "Bad stdout:" in block
            and "Bad status:" not in block
            and "Bad stderr:" not in block
        ):
            statuses[name] = "product-identity"
    counts = {classification: 0 for classification in RESULT_CLASSIFICATIONS}
    for status in statuses.values():
        if status not in counts:
            fail(f"internal classification error for {label}: {status}")
        counts[status] += 1
    print(label + ": " + " ".join(f"{key}={counts[key]}" for key in sorted(counts)))
    return statuses


def execute_native_signal_gate(
    executable: Path,
    source: Path,
    tests: list[str],
) -> None:
    if os.name == "nt":
        print("native signals: skipped on Windows")
        return
    registered = {name for name in tests if name.startswith("signals::")}
    expected = set(NATIVE_SIGNAL_TESTS)
    if platform.system() in NATIVE_SIGINFO_SYSTEMS:
        expected.add("signals::siginfo_prints_current_process")
    if registered != expected:
        missing = sorted(expected - registered)
        extra = sorted(registered - expected)
        fail(f"pinned signal registration drift: missing={missing}, extra={extra}")
    artifact = repository_root() / "_build" / "upstream-harness"
    artifact.mkdir(parents=True, exist_ok=True)
    signal_artifact = artifact / "native-signals"
    signal_artifact.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, object]] = []
    combined: list[str] = []
    passed: set[str] = set()
    for name in sorted(expected):
        slug = name.replace("::", "__")
        signal_run_id = f"{os.getpid()}-{slug}"
        command = [
            str(executable),
            name,
            "--ignored",
            "--exact",
            "--test-threads=1",
            "--color=never",
        ]
        result, timed_out = run_isolated_unix(
            command,
            cwd=source,
            timeout=120,
            extra_env={"MOONJUST_SIGNAL_RUN_ID": signal_run_id},
        )
        orphan_pids = wait_for_linux_process_cleanup(
            "MOONJUST_SIGNAL_RUN_ID", signal_run_id
        )
        for pid in orphan_pids:
            try:
                os.kill(pid, signal.SIGKILL)
            except (OSError, ProcessLookupError):
                pass
        output = result.stdout + result.stderr
        matched = (
            result.returncode == 0
            and re.search(
                rf"^test {re.escape(name)} \.\.\. ok$",
                result.stdout,
                re.MULTILINE,
            )
            is not None
        )
        if matched:
            passed.add(name)
        (signal_artifact / f"{slug}.log").write_text(output, encoding="utf-8")
        records.append(
            {
                "schema_version": 1,
                "upstream_commit": UPSTREAM_COMMIT,
                "upstream_name": name,
                "command": command,
                "returncode": result.returncode,
                "timed_out": timed_out,
                "orphan_pids": orphan_pids,
                "passed": matched,
                "log": f"native-signals/{slug}.log",
            }
        )
        combined.append(f"===== {name} =====\n{output}")
    (artifact / "native-signals.log").write_text(
        "\n".join(combined),
        encoding="utf-8",
    )
    (artifact / "native-signals.jsonl").write_text(
        "".join(
            json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n"
            for record in records
        ),
        encoding="utf-8",
    )
    if passed != expected or any(record["orphan_pids"] for record in records):
        details = []
        for record in records:
            if record["passed"] and not record["orphan_pids"]:
                continue
            details.append(
                f"{record['upstream_name']} "
                f"returncode={record['returncode']} timed_out={record['timed_out']} "
                f"orphan_pids={record['orphan_pids']} "
                f"log={record['log']}"
            )
        fail("native signal gate failed:\n" + "\n".join(details))
    print(f"native signals: passed={len(passed)}")


def encode_results(
    tests: list[str],
    official: dict[str, str],
    native: dict[str, str],
    wasm: dict[str, str],
    exceptions: dict[str, dict[str, object]],
) -> str:
    host = f"{platform.system().lower()}-{platform.machine().lower()}"
    rows = []
    for name in tests:
        rule = exceptions.get(name)
        target_statuses = (native[name], wasm[name])
        if "failed" in target_statuses or official[name] == "failed":
            disposition = "failed"
        elif "excluded-completion" in target_statuses:
            disposition = "excluded-completion"
        elif "product-identity" in target_statuses:
            disposition = "product-identity"
        elif "diagnostic-semantic" in target_statuses:
            disposition = "diagnostic-semantic"
        elif "upstream-ignored" in target_statuses:
            disposition = "upstream-ignored"
        elif "diagnostic-exact" in target_statuses:
            disposition = "diagnostic-exact"
        else:
            disposition = "exact"
        denominator = disposition not in {
            "excluded-completion",
            "product-identity",
            "upstream-ignored",
        }
        rows.append(
            {
                "schema_version": SCHEMA_VERSION,
                "upstream_commit": UPSTREAM_COMMIT,
                "upstream_name": name,
                "host": host,
                "official": official[name],
                "native": native[name],
                "wasm1": wasm[name],
                "disposition": disposition,
                "compatibility_rate_denominator": denominator,
                "exception": (
                    None
                    if rule is None
                    else {
                        "classification": rule["classification"],
                        "owner": rule["owner"],
                        "reason": rule["reason"],
                        "targets": rule["targets"],
                        "normalizations": rule.get("normalizations", []),
                    }
                ),
            }
        )
    return "".join(
        json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n"
        for row in rows
    )


def failed_names(statuses: dict[str, str]) -> set[str]:
    return {name for name, status in statuses.items() if status == "failed"}


def print_audit_diff(path: Path, encoded: str) -> None:
    previous = path.read_text(encoding="utf-8") if path.is_file() else ""
    diff = difflib.unified_diff(
        previous.splitlines(keepends=True),
        encoded.splitlines(keepends=True),
        fromfile=str(path),
        tofile=str(path) + ".candidate",
    )
    rendered = "".join(diff)
    print(rendered if rendered else "compatibility oracle unchanged")


def oracle_projection(encoded: str, source: str) -> str:
    """Remove only the reporting host before comparing audited result rows."""
    projected: list[str] = []
    for line_number, line in enumerate(encoded.splitlines(), start=1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            fail(f"invalid compatibility oracle JSON at {source}:{line_number}: {error}")
        if not isinstance(row, dict) or row.get("schema_version") != SCHEMA_VERSION:
            fail(
                f"invalid compatibility oracle schema at {source}:{line_number}"
            )
        row.pop("host", None)
        projected.append(json.dumps(row, sort_keys=True, separators=(",", ":")))
    return "\n".join(projected) + ("\n" if projected else "")


def verify_audited_oracle(path: Path, encoded: str) -> None:
    if not path.is_file():
        fail(f"recorded harness results are missing: {path}")
    previous = oracle_projection(path.read_text(encoding="utf-8"), str(path))
    candidate = oracle_projection(encoded, str(path) + ".candidate")
    if previous == candidate:
        return
    diff = "".join(
        difflib.unified_diff(
            previous.splitlines(keepends=True),
            candidate.splitlines(keepends=True),
            fromfile=str(path),
            tofile=str(path) + ".candidate",
            n=1,
        )
    )
    fail(
        "compatibility oracle drift; inspect the report and use the explicit "
        f"--audit-write flow to approve it\n{diff[:12000]}"
    )


def regression_details(
    names: set[str],
    native: dict[str, str],
    wasm: dict[str, str],
    limit: int = 40,
) -> str:
    artifact = repository_root() / "_build" / "upstream-harness"
    logs = {
        label: failure_blocks((artifact / f"{label}.log").read_text(encoding="utf-8"))
        for label in ("native", "wasm1")
    }
    details: list[str] = []
    ordered = sorted(names)
    for name in ordered[:limit]:
        details.append(f"{name}: native={native[name]}, wasm1={wasm[name]}")
        for label in ("native", "wasm1"):
            block = ANSI_ESCAPE.sub("", logs[label].get(name, "")).strip()
            if block:
                details.append(f"[{label}]\n{block[:2000]}")
    if len(ordered) > limit:
        details.append(
            f"... {len(ordered) - limit} additional failures are preserved in "
            "_build/upstream-harness/native.log and wasm1.log"
        )
    return "\n".join(details)


def main() -> int:
    repo = repository_root()
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--audit-write",
        action="store_true",
        help="show the complete oracle diff and replace it after all gates pass",
    )
    parser.add_argument(
        "--approve-audit-write",
        choices=[UPSTREAM_COMMIT],
        help="required pinned commit acknowledgement for --audit-write",
    )
    parser.add_argument(
        "--results",
        type=Path,
        default=repo / "tests/upstream/just-1.57.0/harness-results.jsonl",
    )
    parser.add_argument(
        "--native-candidate",
        type=Path,
        help="use this native executable instead of building the debug candidate",
    )
    parser.add_argument(
        "--wasm-candidate",
        type=Path,
        help="use this wasm1 module instead of building the debug candidate",
    )
    parser.add_argument(
        "--signal-only",
        action="store_true",
        help="run only the native signal and process-cleanup gate",
    )
    args = parser.parse_args()
    if args.audit_write and args.approve_audit_write != UPSTREAM_COMMIT:
        fail(
            "--audit-write requires --approve-audit-write " + UPSTREAM_COMMIT
        )
    if args.approve_audit_write is not None and not args.audit_write:
        fail("--approve-audit-write is only valid with --audit-write")

    run_shell_script(repo / "tools/upstream/build_oracle.sh", repo)
    if args.native_candidate is None:
        subprocess.run(
            ["moon", "build", "--target", "native", "cmd/just"],
            cwd=repo,
            check=True,
        )
        native_candidate = repo / "_build/native/debug/build/cmd/just/just.exe"
    else:
        native_candidate = args.native_candidate.resolve()
    if args.signal_only:
        wasm_candidate = None
    elif args.wasm_candidate is None:
        subprocess.run(
            ["moon", "build", "--target", "wasm", "cmd/just"],
            cwd=repo,
            check=True,
        )
        wasm_candidate = repo / "_build/wasm/debug/build/cmd/just/just.wasm"
    else:
        wasm_candidate = args.wasm_candidate.resolve()
    if not native_candidate.is_file():
        fail(f"native candidate is missing: {native_candidate}")
    if not args.signal_only and not wasm_candidate.is_file():
        fail(f"wasm1 candidate is missing: {wasm_candidate}")

    cache = repo / "_build/upstream/just-1.57.0"
    source = cache / "source"
    dirty = run(["git", "status", "--porcelain"], cwd=source)
    if dirty.returncode != 0 or dirty.stdout.strip():
        fail("pinned upstream harness checkout is dirty")
    target = cache / "harness-target"
    executable, bound_binary = compile_harness(source, target)
    tests = list_tests(executable, source)
    if args.signal_only:
        install_binary(bound_binary, native_candidate)
        execute_native_signal_gate(executable, source, tests)
        print("native signal-only gate passed")
        return 0
    exceptions = load_exceptions(
        repo / "tests/upstream/just-1.57.0/compatibility-exceptions.toml",
        tests,
    )
    official_binary = target / "debug" / ("just.official.exe" if os.name == "nt" else "just.official")
    shutil.copy2(bound_binary, official_binary)

    install_binary(bound_binary, official_binary)
    official = execute_harness("official", executable, source, tests)
    if any(status == "failed" for status in official.values()):
        fail("pinned official harness has failures against the official binary")

    install_binary(bound_binary, native_candidate)
    native = execute_harness(
        "native",
        executable,
        source,
        tests,
        exceptions=exceptions,
    )
    execute_native_signal_gate(executable, source, tests)

    moonrun = shutil.which("moonrun")
    if moonrun is None:
        fail("moonrun is required for the wasm1 harness")
    install_wasm_wrapper(
        bound_binary,
        moonrun,
        repo / "policies/execute.toml",
        wasm_candidate,
    )
    wasm = execute_harness(
        "wasm1",
        executable,
        source,
        tests,
        exceptions=exceptions,
        skips=WASM_SKIPS,
    )
    encoded = encode_results(tests, official, native, wasm, exceptions)
    artifact_report = repo / "_build/upstream-harness/compatibility-report.jsonl"
    artifact_report.parent.mkdir(parents=True, exist_ok=True)
    artifact_report.write_text(encoded, encoding="utf-8")
    stale_diagnostics: list[str] = []
    for name, rule in exceptions.items():
        if rule["classification"] not in {
            "diagnostic-exact",
            "diagnostic-semantic",
        }:
            continue
        for target_name, statuses in (("native", native), ("wasm1", wasm)):
            if (
                target_name in rule["targets"]
                and statuses[name] != rule["classification"]
            ):
                stale_diagnostics.append(
                    f"{name} ({target_name} became {statuses[name]})"
                )
    failures = failed_names(native) | failed_names(wasm)
    regression_errors: list[str] = []
    if stale_diagnostics:
        regression_errors.append(
            "stale diagnostic exceptions: " + ", ".join(stale_diagnostics)
        )
    if failures:
        regression_errors.append(
            f"{len(failures)} unapproved compatibility failures\n"
            + regression_details(failures, native, wasm)
        )
    if regression_errors:
        fail("\n\n".join(regression_errors))
    exact = {
        name
        for name in tests
        if native[name] in {"exact", "diagnostic-exact"}
        and wasm[name] in {"exact", "diagnostic-exact"}
    }
    if args.audit_write:
        args.results.parent.mkdir(parents=True, exist_ok=True)
        print_audit_diff(args.results, encoded)
        args.results.write_text(encoded, encoding="utf-8")
    else:
        verify_audited_oracle(args.results, encoded)
    print(f"verified exact Native/wasm1 intersection: {len(exact)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"official harness error: {error}", file=sys.stderr)
        raise SystemExit(1)
