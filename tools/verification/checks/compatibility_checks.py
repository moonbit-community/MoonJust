#!/usr/bin/env python3
"""Cross-platform compatibility gates formerly implemented by shell scripts.

Each gate is deliberately a Python entrypoint.  Commands are passed to the
executable directly so the same checks work on Windows, macOS, and Linux.
"""

from __future__ import annotations

import difflib
import os
import subprocess
import sys
import tempfile
import shutil
from pathlib import Path

sys.path = [entry for entry in sys.path if Path(entry or ".").resolve() != Path(__file__).parent.resolve()]
import platform


REPO = Path(__file__).resolve().parents[3]


def run(argv: list[str], *, cwd: Path = REPO, env: dict[str, str] | None = None,
        input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        cwd=cwd,
        env=env,
        input=input_text,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def checked(argv: list[str], *, cwd: Path = REPO, env: dict[str, str] | None = None,
            input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    result = run(argv, cwd=cwd, env=env, input_text=input_text)
    if result.returncode:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(argv)}\n"
            f"{result.stdout}{result.stderr}"
        )
    return result


def fail(message: str) -> None:
    raise RuntimeError(message)


def artifact(name: str, default: Path) -> Path:
    return Path(os.environ.get(name, str(default))).resolve()


def oracle() -> Path:
    suffix = "just.exe" if platform.system() == "Windows" else "just"
    return artifact("MOONJUST_ORACLE_CANDIDATE", REPO / "_build/upstream/just-1.57.0/target/release" / suffix)


def native() -> Path:
    return artifact("MOONJUST_NATIVE_CANDIDATE", REPO / "_build/native/debug/build/cmd/just/just.exe")


def wasm() -> Path:
    return artifact("MOONJUST_WASM_CANDIDATE", REPO / "_build/wasm/debug/build/cmd/just/just.wasm")


def ensure_artifacts(*, need_wasm: bool = True, need_native: bool = True, need_oracle: bool = True) -> None:
    if need_oracle and not oracle().is_file():
        checked([sys.executable, "tools/upstream/build_oracle.py"])
    if need_native and not native().is_file() and "MOONJUST_NATIVE_CANDIDATE" not in os.environ:
        checked(["moon", "build", "--target", "native", "cmd/just"])
    if need_wasm and not wasm().is_file() and "MOONJUST_WASM_CANDIDATE" not in os.environ:
        checked(["moon", "build", "--target", "wasm", "cmd/just"])
    for label, path in (("oracle", oracle()), ("native CLI", native()), ("wasm CLI", wasm())):
        if label == "wasm CLI" and not need_wasm:
            continue
        if label == "native CLI" and not need_native:
            continue
        if label == "oracle" and not need_oracle:
            continue
        if not path.is_file():
            fail(f"{label} is missing: {path}")


def compare_files(left: Path, right: Path, label: str) -> None:
    left_text = left.read_text(encoding="utf-8", errors="replace")
    right_text = right.read_text(encoding="utf-8", errors="replace")
    if left_text != right_text:
        diff = "".join(difflib.unified_diff(left_text.splitlines(True), right_text.splitlines(True), fromfile=str(left), tofile=str(right)))
        fail(f"{label} differs\n{diff}")


def query() -> None:
    ensure_artifacts()
    policy = REPO / "policies/inspect.toml"
    fixtures = REPO / "tests/fixtures/query"
    cases = [
        ("query", fixtures / "query.justfile", ["--list"]),
        ("list-left", fixtures / "query.justfile", ["--list", "--alias-style", "left"]),
        ("list-separate", fixtures / "query.justfile", ["--list", "--alias-style", "separate"]),
        ("summary", fixtures / "query.justfile", ["--summary"]),
        ("groups", fixtures / "query.justfile", ["--groups"]),
        ("variables", fixtures / "query.justfile", ["--variables"]),
        ("evaluate", fixtures / "query.justfile", ["--evaluate"]),
        ("evaluate-one", fixtures / "query.justfile", ["--evaluate", "y"]),
        ("dump", fixtures / "query.justfile", ["--dump"]),
        ("json", fixtures / "query.justfile", ["--unstable", "--json"]),
        ("json-arg", fixtures / "json-arg.justfile", ["--unstable", "--dump", "--dump-format", "json"]),
        ("list-options", fixtures / "json-arg.justfile", ["--unstable", "--list"]),
        ("usage-options", fixtures / "json-arg.justfile", ["--unstable", "--usage", "foo"]),
        ("json-settings", fixtures / "json-settings.justfile", ["--unstable", "--dump", "--dump-format", "json"]),
        ("json-attributes", fixtures / "json-attributes.justfile", ["--unstable", "--dump", "--dump-format", "json"]),
        ("list-groups", fixtures / "groups.justfile", ["--list"]),
        ("list-groups-unsorted", fixtures / "groups.justfile", ["--list", "--unsorted"]),
        ("list-selected-groups", fixtures / "groups.justfile", ["--list", "--group", "alpha", "--group", "beta"]),
        ("multiple-groups", fixtures / "groups.justfile", ["--groups"]),
        ("show", fixtures / "query.justfile", ["--show", "h"]),
        ("usage", fixtures / "query.justfile", ["--usage", "h"]),
        ("show-suggestion", fixtures / "query.justfile", ["--show", "hell"]),
        ("show-no-suggestion", fixtures / "query.justfile", ["--show", "zzzzzzzz"]),
        ("summary-empty", fixtures / "empty.justfile", ["--summary"]),
    ]
    with tempfile.TemporaryDirectory(prefix="moonjust-query-") as raw:
        work = Path(raw)
        for name, fixture, args in cases:
            commands = {
                "oracle": [str(oracle()), "--justfile", str(fixture), *args],
                "native": [str(native()), "--justfile", str(fixture), *args],
                "wasm": ["moonrun", "--policy", str(policy), str(wasm()), "--justfile", str(fixture), *args],
            }
            results = {key: run(value) for key, value in commands.items()}
            for key in ("native", "wasm"):
                if results[key].returncode != results["oracle"].returncode:
                    fail(f"{name} {key} exit status differs")
                if results[key].stdout != results["oracle"].stdout or results[key].stderr != results["oracle"].stderr:
                    fail(f"{name} {key} output differs")
            (work / f"{name}.ok").write_text("ok\n", encoding="utf-8")
    print(f"Query compatibility verified: {len(cases)} Native/Wasm cases")


def hostfs() -> None:
    allow_policy = REPO / "policies/filesystem.toml"
    deny_policy = REPO / "policies/inspect.toml"
    allow_text = allow_policy.read_text(encoding="utf-8")
    deny_text = deny_policy.read_text(encoding="utf-8")
    if 'write = ["../"]' not in allow_text or "write = []" not in deny_text:
        fail("HostFs policies do not have the expected write scope")
    checked(["moon", "build", "--target", "wasm", "tools/probes/hostfs_probe"])
    binary = REPO / "_build/wasm/debug/build/tools/probes/hostfs_probe/hostfs_probe.wasm"
    if not binary.is_file():
        fail(f"HostFs probe is missing: {binary}")
    with tempfile.TemporaryDirectory(prefix="moonjust-hostfs-") as raw:
        work = Path(raw)
        allow = run(["moonrun", "--policy", str(allow_policy), str(binary), "allow"])
        if allow.returncode or allow.stdout.strip() != "allow: atomic replace, CRLF, no-overwrite, cleanup" or allow.stderr:
            fail("allowed HostFs transaction changed")
        deny = run(["moonrun", "--policy", str(deny_policy), str(binary), "deny"])
        if deny.returncode or deny.stdout.strip() != "deny: typed write denial, cleanup":
            fail("denied HostFs transaction changed")
        lines = [line for line in deny.stderr.splitlines() if line]
        if len(lines) != 2 or len(set(lines)) != 1:
            fail("denied HostFs diagnostics changed")
    print("HostFs policies verified")


def dotenv() -> None:
    with tempfile.TemporaryDirectory(prefix="moonjust-dotenv-") as raw:
        work = Path(raw)
        target = REPO / "_build/dotenvy-oracle"
        checked(["cargo", "build", "--quiet", "--locked", "--manifest-path", str(REPO / "tools/oracles/dotenvy/Cargo.toml")], env={**os.environ, "CARGO_TARGET_DIR": str(target)})
        oracle_bin = target / "debug/moonjust-dotenvy-oracle"
        if not oracle_bin.is_file():
            fail("dotenv oracle is missing")
        for name in ("basic", "substitution", "multiline"):
            fixture = REPO / "tests/fixtures/dotenv" / f"{name}.env"
            env = {**os.environ, "KEY11": "ambient"}
            expected = run([str(oracle_bin)], env=env, input_text=fixture.read_text(encoding="utf-8"))
            actual = run(["moon", "run", "--quiet", "--target", "native", "tools/probes/dotenv_probe"], input_text=fixture.read_text(encoding="utf-8"))
            if expected.returncode != actual.returncode or expected.stdout != actual.stdout:
                fail(f"dotenv fixture differs: {name}")
        crlf = work / "crlf.env"
        crlf.write_bytes(b"CRLF=accepted\r\nSECOND=line\r\n")
        expected = run([str(oracle_bin)], env={**os.environ, "KEY11": "ambient"}, input_text=crlf.read_text(encoding="utf-8"))
        actual = run(["moon", "run", "--quiet", "--target", "native", "tools/probes/dotenv_probe"], input_text=crlf.read_text(encoding="utf-8"))
        if expected.returncode != actual.returncode or expected.stdout != actual.stdout:
            fail("dotenv CRLF fixture differs")
        for name, data in (("invalid", "top-secret=hidden\n"), ("bom", "\ufeffBOM=rejected\n")):
            fixture = work / f"{name}.env"
            fixture.write_text(data, encoding="utf-8")
            expected = run([str(oracle_bin)], env={**os.environ, "KEY11": "ambient"}, input_text=data)
            actual = run(["moon", "run", "--quiet", "--target", "native", "tools/probes/dotenv_probe"], input_text=data)
            if expected.returncode == 0 or actual.returncode == 0:
                fail(f"invalid dotenv fixture was accepted: {name}")
            if "top-secret" in actual.stderr:
                fail("dotenv diagnostic disclosed a value")
    print("Dotenv differential passed")


def invocation() -> None:
    ensure_artifacts(need_wasm=True, need_native=True, need_oracle=True)
    checked(["moon", "build", "--quiet", "--target", "native", "tools/probes/invocation_probe"])
    probe = REPO / "_build/native/debug/build/tools/probes/invocation_probe/invocation_probe.exe"
    fixture = REPO / "tests/fixtures/invocation/invocation.justfile"
    policy = REPO / "policies/inspect.toml"
    if not probe.is_file():
        fail("invocation probe is missing")
    cases = [
        ("long-short", ["probe", "--first", "alpha", "-s", "tail", "one", "two"]),
        ("equals-terminator", ["probe", "--first=beta", "-s", "--", "--literal", "-x"]),
        ("pattern-list", ["build", "--kind", "release"]),
        ("positional-explicit", ["plain", "value", "override"]),
        ("value-expression", ["computed", "hello", "--selected"]),
        ("multiple-value", ["expanded", "--repeat", "--repeat"]),
    ]
    with tempfile.TemporaryDirectory(prefix="moonjust-invocation-") as raw:
        work = Path(raw)
        for name, args in cases:
            upstream = run([str(oracle()), "--unstable", "--dry-run", "--justfile", str(fixture), *args])
            candidate = run([str(probe), *args], input_text=fixture.read_text(encoding="utf-8"))
            if upstream.returncode != candidate.returncode or upstream.stderr != candidate.stdout:
                fail(f"{name} rendered invocation differs")
        for name, args in (("usage-probe", ["probe"]), ("usage-build", ["build"]), ("usage-plain", ["plain"])):
            upstream = run([str(oracle()), "--unstable", "--justfile", str(fixture), "--usage", *args])
            native_result = run([str(native()), "--unstable", "--justfile", str(fixture), "--usage", *args])
            wasm_result = run(["moonrun", "--policy", str(policy), str(wasm()), "--unstable", "--justfile", str(fixture), "--usage", *args])
            for candidate in (native_result, wasm_result):
                if candidate.returncode != upstream.returncode or candidate.stdout != upstream.stdout or candidate.stderr != upstream.stderr:
                    fail(f"{name} output differs")
    print("Invocation differential passed")


def workdir() -> None:
    ensure_artifacts()
    checked(["moon", "build", "--quiet", "--target", "native", "tools/probes/workdir_probe"])
    probe = REPO / "_build/native/debug/build/tools/probes/workdir_probe/workdir_probe.exe"
    if not probe.is_file():
        fail("working-directory probe is missing")
    with tempfile.TemporaryDirectory(prefix="moonjust-workdir-") as raw:
        root = Path(raw)
        (root / "inv").mkdir()
        (root / "includes").mkdir()
        (root / "modules/release").mkdir(parents=True)
        (root / "config").mkdir()
        (root / "run").mkdir()
        (root / "link/sub").mkdir(parents=True)
        (root / "source.just").write_text("default:\n  @pwd -P\n", encoding="utf-8")
        try:
            (root / "link/justfile").symlink_to("../source.just")
        except OSError:
            pass
        cases = {
            "project": "default:\n  @pwd -P\n",
            "no-cd": "[no-cd]\ndefault:\n  @pwd -P\n",
            "setting": "set working-directory := 'build'\n\ndefault:\n  @pwd -P\n",
            "setting-attribute": "set working-directory := 'build'\n\n[working-directory('release')]\ndefault:\n  @pwd -P\n",
            "attribute-over-no-cd": "set no-cd := true\n\n[working-directory('release')]\ndefault:\n  @pwd -P\n",
        }
        for name, text in cases.items():
            (root / "justfile").write_text(text, encoding="utf-8")
            actual = run([str(probe), str(root), name])
            if actual.returncode:
                fail(f"working-directory probe failed: {name}: {actual.stderr}")
    print("Working-directory differential passed")


def environment() -> None:
    ensure_artifacts(need_wasm=False)
    checked(["moon", "build", "--quiet", "--target", "native", "tools/probes/environment_probe"])
    probe = REPO / "_build/native/debug/build/tools/probes/environment_probe/environment_probe.exe"
    if not probe.is_file():
        fail("environment probe is missing")
    for name in ("set", "shell-two", "shell-clear", "shell-reset", "precedence"):
        result = run([str(probe), name])
        if result.returncode:
            fail(f"environment probe failed: {name}: {result.stderr}")
    print("Environment differential passed")


def executor() -> None:
    ensure_artifacts(need_wasm=True, need_native=True, need_oracle=True)
    fixture = REPO / "tests/fixtures/execution/line.justfile"
    expected = REPO / "tests/fixtures/execution/line.dry-run.stderr"
    dry_run = run([str(oracle()), "--dry-run", "--justfile", str(fixture), "build"])
    if dry_run.returncode or dry_run.stdout or dry_run.stderr != expected.read_text(encoding="utf-8"):
        fail("ordinary-line oracle output changed")
    checked(["moon", "test", "--target", "native", "src/executor"])
    checked(["moon", "test", "--target", "wasm", "src/executor"])
    with tempfile.TemporaryDirectory(prefix="moonjust-executor-") as raw:
        work = Path(raw)
        native_result = run([str(native()), "--justfile", str(fixture), "build"], cwd=work)
        wasm_result = run(["moonrun", "--policy", str(REPO / "policies/execute.toml"), str(wasm()), "--justfile", str(fixture), "build"], cwd=work)
        if native_result.returncode or wasm_result.returncode or native_result.stdout != wasm_result.stdout:
            fail("native/wasm executor output differs")
    print("Executor gate passed")


def runtime() -> None:
    for target, packages in (("native", ("src/scheduler", "src/cache", "src/runtime", "src/host_native", "src/host_process")),
                             ("wasm", ("src/scheduler", "src/cache", "src/runtime", "src/host_wasm", "src/host_process"))):
        for package in packages:
            checked(["moon", "test", "--target", target, package])
    ensure_artifacts(need_wasm=True, need_native=True, need_oracle=False)
    fixture = REPO / "tests/fixtures/runtime/justfile"
    with tempfile.TemporaryDirectory(prefix="moonjust-runtime-") as raw:
        work = Path(raw)
        shutil.copy2(REPO / "tests/fixtures/runtime/justfile", work / "justfile")
        (work / "input").write_text("one\n", encoding="utf-8")
        native_result = run([str(native()), "--unstable", "--jobs", "2", "root"], cwd=work)
        wasm_result = run(["moonrun", "--policy", str(REPO / "policies/execute.toml"), str(wasm()), "--unstable", "--jobs", "2", "root"], cwd=work)
        if native_result.returncode or wasm_result.returncode:
            fail("runtime parallel smoke failed")
    print("Runtime gate passed")


def inspect() -> None:
    ensure_artifacts(need_wasm=True, need_native=False, need_oracle=False)
    policy = REPO / "policies/inspect.toml"
    text = policy.read_text(encoding="utf-8")
    if "write = []" not in text or "spawn = false" not in text:
        fail("inspect policy grants writes or process spawn")
    fixture = REPO / "tests/fixtures/query/justfile"
    result = run(["moonrun", "--policy", str(policy), str(wasm()), "--list", "--justfile", str(fixture)])
    if result.returncode or "hello" not in result.stdout or result.stderr:
        fail("inspect list smoke changed")
    print("Wasm inspect policy verified")


GATES = {
    "query": query,
    "hostfs": hostfs,
    "dotenv": dotenv,
    "invocation": invocation,
    "workdir": workdir,
    "environment": environment,
    "executor": executor,
    "runtime": runtime,
    "inspect": inspect,
}


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in GATES:
        raise SystemExit("usage: compatibility_checks.py " + "|".join(GATES))
    GATES[sys.argv[1]]()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
