#!/usr/bin/env python3
"""Run pinned-just differential cases against Native and wasm candidates."""

from __future__ import annotations

import argparse
import hashlib
import os
import selectors
import shutil
import signal
import subprocess
import sys
import time
import tomllib
from dataclasses import dataclass
from pathlib import Path


DEFAULT_COMPARE = ("status", "stdout", "stderr", "tree")
ALLOWED_COMPARE = {*DEFAULT_COMPARE, "merged", "live"}
ALLOWED_DIFFERENCES = {"none", "product-identity", "diagnostic-style", "completion-scope"}


@dataclass(frozen=True)
class Case:
    case_id: str
    directory: str
    expectation: str
    compare: tuple[str, ...]
    upstream_tests: tuple[str, ...]
    allowed_difference: str
    live_stream: str | None
    live_prefix: bytes
    live_timeout_ms: int
    signal_name: str | None
    signal_after_prefix: bytes
    cwd: str


@dataclass(frozen=True)
class Command:
    name: str
    argv: tuple[str, ...]


def fail(message: str) -> None:
    raise ValueError(message)


def remove_tree(path: Path) -> None:
    """Remove one resolved case directory, tolerating delayed filesystem updates."""
    for attempt in range(5):
        if not path.exists():
            return
        try:
            shutil.rmtree(path)
            return
        except OSError:
            if attempt == 4:
                raise
            time.sleep(0.05 * (attempt + 1))


def load_cases(manifest_path: Path) -> list[Case]:
    manifest = tomllib.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 2:
        fail("differential manifest schema_version must be 2")
    rows = manifest.get("case", [])
    if not rows:
        fail("differential manifest contains no cases")
    result: list[Case] = []
    seen: set[str] = set()
    for row in rows:
        case_id = row.get("id")
        if not isinstance(case_id, str) or not case_id or case_id in seen:
            fail(f"invalid or duplicate differential case id: {case_id!r}")
        seen.add(case_id)
        directory = row.get("directory")
        if not isinstance(directory, str) or not directory:
            fail(f"{case_id} has no directory")
        expectation = row.get("status")
        if expectation not in {"match", "expected-difference"}:
            fail(f"{case_id} has invalid status {expectation!r}")
        compare = tuple(row.get("compare", DEFAULT_COMPARE))
        if not compare or any(item not in ALLOWED_COMPARE for item in compare):
            fail(f"{case_id} has invalid compare fields")
        upstream_tests = tuple(row.get("upstream_tests", []))
        if any(not isinstance(item, str) or not item for item in upstream_tests):
            fail(f"{case_id} has invalid upstream_tests")
        allowed_difference = row.get("allowed_difference", "none")
        if allowed_difference not in ALLOWED_DIFFERENCES:
            fail(f"{case_id} has invalid allowed_difference")
        if expectation == "match" and allowed_difference != "none":
            fail(f"{case_id} cannot allow a difference while requiring a match")
        if expectation == "expected-difference" and allowed_difference == "none":
            fail(f"{case_id} expected difference lacks a bounded difference kind")
        live_stream = row.get("live_stream")
        if live_stream not in {None, "stdout", "stderr", "merged"}:
            fail(f"{case_id} has invalid live_stream")
        live_prefix_text = row.get("live_prefix", "")
        if not isinstance(live_prefix_text, str):
            fail(f"{case_id} has invalid live_prefix")
        live_timeout_ms = row.get("live_timeout_ms", 1000)
        if not isinstance(live_timeout_ms, int) or live_timeout_ms <= 0:
            fail(f"{case_id} has invalid live_timeout_ms")
        signal_name = row.get("signal")
        if signal_name is not None and signal_name not in {"SIGHUP", "SIGINT", "SIGTERM"}:
            fail(f"{case_id} has unsupported signal {signal_name!r}")
        signal_prefix_text = row.get("signal_after_prefix", "")
        if not isinstance(signal_prefix_text, str):
            fail(f"{case_id} has invalid signal_after_prefix")
        if "live" in compare and (live_stream is None or not live_prefix_text):
            fail(f"{case_id} live comparison requires live_stream and live_prefix")
        cwd = row.get("cwd", ".")
        if not isinstance(cwd, str) or not cwd or Path(cwd).is_absolute() or ".." in Path(cwd).parts:
            fail(f"{case_id} has invalid relative cwd")
        result.append(
            Case(
                case_id=case_id,
                directory=directory,
                expectation=expectation,
                compare=compare,
                upstream_tests=upstream_tests,
                allowed_difference=allowed_difference,
                live_stream=live_stream,
                live_prefix=live_prefix_text.encode(),
                live_timeout_ms=live_timeout_ms,
                signal_name=signal_name,
                signal_after_prefix=signal_prefix_text.encode(),
                cwd=cwd,
            )
        )
    return result


def expand_fixture_value(value: str, run_root: Path) -> str:
    return (
        value.replace("<CASE_ROOT>", str(run_root))
        .replace("<TAB>", "\t")
        .replace("<TWO_SPACES>", "  ")
    )


def read_arguments(case_dir: Path, run_root: Path) -> list[str]:
    path = case_dir / "argv.txt"
    if not path.exists():
        return []
    return [
        expand_fixture_value(value, run_root)
        for value in path.read_text(encoding="utf-8").splitlines()
    ]


def read_environment(case_dir: Path, run_root: Path) -> dict[str, str]:
    environment = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "HOME": str(run_root / "home"),
        "LC_ALL": "C",
        "LANG": "C",
        "TZ": "UTC",
        "JUST_COLOR": "never",
    }
    path = case_dir / "env.list"
    if not path.exists():
        return environment
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line:
            continue
        name, separator, value = line.partition("=")
        if not separator or not name.replace("_", "a").isalnum() or name[0].isdigit():
            fail(f"invalid environment assignment in {path}: {line!r}")
        environment[name] = expand_fixture_value(value, run_root)
    return environment


def snapshot_tree(root: Path) -> bytes:
    rows: list[str] = []
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = "./" + path.relative_to(root).as_posix()
        if path.is_symlink():
            rows.append(f"link\t{relative}\t{os.readlink(path)}")
        elif path.is_dir():
            rows.append(f"dir\t{relative}")
        elif path.is_file():
            rows.append(f"file\t{relative}\t{hashlib.sha256(path.read_bytes()).hexdigest()}")
        else:
            rows.append(f"other\t{relative}")
    return ("\n".join(rows) + ("\n" if rows else "")).encode()


def normalize(data: bytes, run_root: Path) -> bytes:
    return data.replace(str(run_root).encode(), b"<CASE_ROOT>")


def capture_process(
    argv: list[str],
    cwd: Path,
    environment: dict[str, str],
    stdin: bytes,
    merged: bool,
    live_stream: str | None,
    live_prefix: bytes,
    live_timeout_ms: int,
    signal_name: str | None,
    signal_after_prefix: bytes,
) -> tuple[int, bytes, bytes, bool]:
    process = subprocess.Popen(
        argv,
        cwd=cwd,
        env=environment,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT if merged else subprocess.PIPE,
        start_new_session=True,
    )
    assert process.stdin is not None and process.stdout is not None
    process.stdin.write(stdin)
    process.stdin.close()
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "merged" if merged else "stdout")
    if process.stderr is not None:
        selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    output = {"stdout": bytearray(), "stderr": bytearray(), "merged": bytearray()}
    deadline = time.monotonic() + live_timeout_ms / 1000
    live_observed = live_stream is None
    signal_sent = signal_name is None
    while selector.get_map():
        events = selector.select(timeout=0.05)
        for key, _ in events:
            chunk = os.read(key.fileobj.fileno(), 65536)
            if not chunk:
                selector.unregister(key.fileobj)
                key.fileobj.close()
                continue
            stream = key.data
            output[stream].extend(chunk)
            if live_stream == stream and live_prefix in output[stream] and time.monotonic() <= deadline:
                live_observed = True
            combined = bytes(output[stream])
            if not signal_sent and (not signal_after_prefix or signal_after_prefix in combined):
                os.killpg(process.pid, getattr(signal, signal_name))
                signal_sent = True
        if not signal_sent and process.poll() is not None:
            signal_sent = True
    status = process.wait()
    return status, bytes(output["stdout"]), bytes(output["stderr"]), live_observed


def prepare_root(case_dir: Path, run_root: Path) -> None:
    if run_root.exists():
        remove_tree(run_root)
    (run_root / "home").mkdir(parents=True)
    tree = case_dir / "tree"
    if tree.is_dir():
        shutil.copytree(tree, run_root, dirs_exist_ok=True, symlinks=True)


def run_side(command: Command, case: Case, case_dir: Path, artifact_dir: Path) -> dict[str, bytes]:
    run_root = artifact_dir / f"{command.name}-root"
    prepare_root(case_dir, run_root)
    (run_root / case.cwd).mkdir(parents=True, exist_ok=True)
    stdin_path = case_dir / "stdin"
    stdin = stdin_path.read_bytes() if stdin_path.exists() else b""
    argv = [*command.argv, *read_arguments(case_dir, run_root)]
    status, stdout, stderr, live = capture_process(
        argv,
        run_root / case.cwd,
        read_environment(case_dir, run_root),
        stdin,
        False,
        case.live_stream if case.live_stream != "merged" else None,
        case.live_prefix,
        case.live_timeout_ms,
        case.signal_name,
        case.signal_after_prefix,
    )
    artifacts = {
        "status": f"{status}\n".encode(),
        "stdout": normalize(stdout, run_root),
        "stderr": normalize(stderr, run_root),
        "tree": snapshot_tree(run_root),
        "live": ("pass\n" if live else "fail\n").encode(),
    }
    if "merged" in case.compare:
        merged_root = artifact_dir / f"{command.name}-merged-root"
        prepare_root(case_dir, merged_root)
        (merged_root / case.cwd).mkdir(parents=True, exist_ok=True)
        merged_status, merged, _, merged_live = capture_process(
            argv,
            merged_root / case.cwd,
            read_environment(case_dir, merged_root),
            stdin,
            True,
            "merged" if case.live_stream == "merged" else None,
            case.live_prefix,
            case.live_timeout_ms,
            case.signal_name,
            case.signal_after_prefix,
        )
        artifacts["merged"] = normalize(merged, merged_root)
        if "status" in case.compare and merged_status != status:
            fail(f"{case.case_id} {command.name} split and merged status differ")
        if case.live_stream == "merged":
            artifacts["live"] = ("pass\n" if merged_live else "fail\n").encode()
    for name, data in artifacts.items():
        (artifact_dir / f"{command.name}.{name}").write_bytes(data)
    return artifacts


def compare_side(
    case: Case,
    upstream: dict[str, bytes],
    candidate: dict[str, bytes],
    candidate_name: str,
    artifact_dir: Path,
) -> set[str]:
    differences: set[str] = set()
    for field in case.compare:
        left = upstream[field]
        right = candidate[field]
        if left == right:
            continue
        differences.add(field)
        (artifact_dir / f"{candidate_name}.{field}.diff").write_text(
            f"upstream {field}: {left!r}\n{candidate_name} {field}: {right!r}\n",
            encoding="utf-8",
        )
    return differences


def bounded_difference(kind: str, fields: set[str]) -> bool:
    if not fields:
        return False
    if kind == "product-identity":
        return fields <= {"stdout", "stderr", "merged"}
    if kind == "diagnostic-style":
        return fields <= {"stderr", "merged"}
    if kind == "completion-scope":
        return fields <= {"stdout", "stderr", "merged"}
    return False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--candidate-native", type=Path)
    parser.add_argument("--candidate-wasm", type=Path)
    parser.add_argument("--moonrun", default="moonrun")
    parser.add_argument("--wasm-policy", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--cases", type=Path)
    parser.add_argument("--artifacts", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parents[2]
    manifest = (args.manifest or repo / "tests/differential/cases.toml").resolve()
    cases_root = (args.cases or manifest.parent / "cases").resolve()
    artifacts_root = (args.artifacts or repo / "_build/differential").resolve()
    upstream_path = args.upstream.resolve()
    native_path = (args.candidate_native or args.candidate)
    if not upstream_path.is_file() or not os.access(upstream_path, os.X_OK):
        fail(f"upstream binary is not executable: {upstream_path}")
    if native_path is None and args.candidate_wasm is None:
        fail("at least one candidate is required")
    commands = [Command("upstream", (str(upstream_path),))]
    if native_path is not None:
        native_path = native_path.resolve()
        if not native_path.is_file() or not os.access(native_path, os.X_OK):
            fail(f"Native candidate is not executable: {native_path}")
        commands.append(Command("native", (str(native_path),)))
    if args.candidate_wasm is not None:
        wasm_path = args.candidate_wasm.resolve()
        if not wasm_path.is_file():
            fail(f"wasm candidate is missing: {wasm_path}")
        if args.wasm_policy is None:
            fail("--candidate-wasm requires --wasm-policy")
        commands.append(
            Command(
                "wasm",
                (args.moonrun, "--policy", str(args.wasm_policy.resolve()), str(wasm_path)),
            )
        )
    cases = load_cases(manifest)
    artifacts_root.mkdir(parents=True, exist_ok=True)
    matched = expected_differences = failures = 0
    for case in cases:
        case_dir = cases_root / case.directory
        if not case_dir.is_dir():
            fail(f"case directory not found: {case_dir}")
        artifact_dir = artifacts_root / case.directory
        if artifact_dir.exists():
            remove_tree(artifact_dir)
        artifact_dir.mkdir(parents=True)
        results = {command.name: run_side(command, case, case_dir, artifact_dir) for command in commands}
        observations = [
            compare_side(case, results["upstream"], results[command.name], command.name, artifact_dir)
            for command in commands[1:]
        ]
        observed_match = all(not fields for fields in observations)
        if case.expectation == "match" and observed_match:
            matched += 1
            print(f"PASS  {case.directory} (match)")
        elif case.expectation == "expected-difference" and all(
            bounded_difference(case.allowed_difference, fields) for fields in observations
        ):
            expected_differences += 1
            print(f"XDIFF {case.directory} ({case.case_id}, {case.allowed_difference})")
        else:
            failures += 1
            print(
                f"FAIL  {case.directory} (expected {case.expectation}, observed "
                f"{'match' if observed_match else 'difference'})",
                file=sys.stderr,
            )
    print(
        f"total={len(cases)} matched={matched} "
        f"expected_differences={expected_differences} failures={failures}"
    )
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, tomllib.TOMLDecodeError) as error:
        print(f"differential error: {error}", file=sys.stderr)
        raise SystemExit(2)
