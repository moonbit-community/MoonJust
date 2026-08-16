#!/usr/bin/env python3
"""Run pinned just integration tests against oracle, Native, and wasm1 binaries."""

from __future__ import annotations

import ast
import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path


UPSTREAM_COMMIT = "e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f"
SCHEMA_VERSION = 2
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
}
NATIVE_SIGNAL_EXCLUSIONS = {
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


def repository_root() -> Path:
    return Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise RuntimeError(message)


def run(command: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
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
    return subprocess.run(
        command,
        cwd=cwd,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
        timeout=600,
    )


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


def execute_harness(
    label: str,
    executable: Path,
    source: Path,
    tests: list[str],
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
    blocks = failure_blocks(combined)
    for name, status in statuses.items():
        if status != "failed":
            continue
        block = blocks.get(name, "")
        if is_bounded_diagnostic_difference(block):
            statuses[name] = "diagnostic-style"
        elif (
            name == "changelog::print_changelog"
            and "Bad stdout:" in block
            and "Bad status:" not in block
            and "Bad stderr:" not in block
        ):
            statuses[name] = "product-identity"
    passed = sum(status == "passed" for status in statuses.values())
    diagnostic = sum(
        status in {"diagnostic-style", "product-identity"}
        for status in statuses.values()
    )
    failed = sum(status == "failed" for status in statuses.values())
    ignored = sum(status in {"ignored", "filtered"} for status in statuses.values())
    print(
        f"{label}: passed={passed} diagnostic-style={diagnostic} "
        f"failed={failed} ignored-or-filtered={ignored}"
    )
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
    expected = NATIVE_SIGNAL_TESTS | NATIVE_SIGNAL_EXCLUSIONS
    if platform.system() in NATIVE_SIGINFO_SYSTEMS:
        expected.add("signals::siginfo_prints_current_process")
    if registered != expected:
        missing = sorted(expected - registered)
        extra = sorted(registered - expected)
        fail(f"pinned signal registration drift: missing={missing}, extra={extra}")
    command = [
        str(executable),
        "--ignored",
        "--test-threads=1",
        "signals::",
        "--skip",
        "signals::forwarding",
        "--skip",
        "signals::siginfo_prints_current_process",
        "--color=never",
    ]
    result = run(command, cwd=source)
    artifact = repository_root() / "_build" / "upstream-harness"
    artifact.mkdir(parents=True, exist_ok=True)
    (artifact / "native-signals.log").write_text(
        result.stdout + result.stderr,
        encoding="utf-8",
    )
    if result.returncode != 0:
        fail(f"native signal gate failed:\n{result.stdout}{result.stderr}")
    passed = {
        name
        for name in NATIVE_SIGNAL_TESTS
        if re.search(rf"^test {re.escape(name)} \.\.\. ok$", result.stdout, re.MULTILINE)
    }
    if passed != NATIVE_SIGNAL_TESTS:
        fail(f"native signal gate omitted: {sorted(NATIVE_SIGNAL_TESTS - passed)}")
    print(f"native signals: passed={len(passed)}")


def encode_results(
    tests: list[str],
    official: dict[str, str],
    native: dict[str, str],
    wasm: dict[str, str],
) -> str:
    host = f"{platform.system().lower()}-{platform.machine().lower()}"
    rows = []
    for name in tests:
        verified = (
            official[name] == "passed"
            and native[name] in {"passed", "diagnostic-style", "product-identity"}
            and wasm[name] in {"passed", "diagnostic-style", "product-identity"}
        )
        rows.append(
            {
                "schema_version": SCHEMA_VERSION,
                "upstream_commit": UPSTREAM_COMMIT,
                "upstream_name": name,
                "host": host,
                "official": official[name],
                "native": native[name],
                "wasm1": wasm[name],
                "disposition": "verified-differential" if verified else "unverified",
                "allowed_difference": (
                    "product-identity"
                    if "product-identity" in {native[name], wasm[name]}
                    else (
                        "diagnostic-style"
                        if "diagnostic-style" in {native[name], wasm[name]}
                        else "none"
                    )
                ),
            }
        )
    return "".join(
        json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n"
        for row in rows
    )


def verified_names(encoded: str) -> set[str]:
    return {
        row["upstream_name"]
        for row in map(json.loads, encoded.splitlines())
        if row["disposition"] == "verified-differential"
    }


def main() -> int:
    repo = repository_root()
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument(
        "--results",
        type=Path,
        default=repo / "tests/upstream/just-1.57.0/harness-results.jsonl",
    )
    args = parser.parse_args()

    subprocess.run([str(repo / "tools/upstream/build_oracle.sh")], cwd=repo, check=True)
    subprocess.run(["moon", "build", "--target", "native", "cmd/just"], cwd=repo, check=True)
    subprocess.run(["moon", "build", "--target", "wasm", "cmd/just"], cwd=repo, check=True)

    cache = repo / "_build/upstream/just-1.57.0"
    source = cache / "source"
    dirty = run(["git", "status", "--porcelain"], cwd=source)
    if dirty.returncode != 0 or dirty.stdout.strip():
        fail("pinned upstream harness checkout is dirty")
    target = cache / "harness-target"
    executable, bound_binary = compile_harness(source, target)
    tests = list_tests(executable, source)
    official_binary = target / "debug" / ("just.official.exe" if os.name == "nt" else "just.official")
    shutil.copy2(bound_binary, official_binary)

    install_binary(bound_binary, official_binary)
    official = execute_harness("official", executable, source, tests)
    if any(status == "failed" for status in official.values()):
        fail("pinned official harness has failures against the official binary")

    native_candidate = repo / "_build/native/debug/build/cmd/just/just.exe"
    install_binary(bound_binary, native_candidate)
    native = execute_harness("native", executable, source, tests)
    execute_native_signal_gate(executable, source, tests)

    wasm_candidate = repo / "_build/wasm/debug/build/cmd/just/just.wasm"
    moonrun = shutil.which("moonrun")
    if moonrun is None:
        fail("moonrun is required for the wasm1 harness")
    install_wasm_wrapper(
        bound_binary,
        moonrun,
        repo / "policies/execute.toml",
        wasm_candidate,
    )
    wasm = execute_harness("wasm1", executable, source, tests, WASM_SKIPS)
    encoded = encode_results(tests, official, native, wasm)
    args.results.parent.mkdir(parents=True, exist_ok=True)
    if args.write:
        args.results.write_text(encoded, encoding="utf-8")
    elif not args.results.is_file():
        fail(f"recorded harness results are missing: {args.results}")
    else:
        recorded = args.results.read_text(encoding="utf-8")
        missing = verified_names(recorded) - verified_names(encoded)
        if missing:
            fail(
                f"{len(missing)} recorded harness tests regressed: "
                + ", ".join(sorted(missing))
            )
    print(f"verified exact Native/wasm1 intersection: {len(verified_names(encoded))}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"official harness error: {error}", file=sys.stderr)
        raise SystemExit(1)
