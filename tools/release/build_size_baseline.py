#!/usr/bin/env python3
"""Build a same-run merge-base artifact baseline for release size comparisons."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dependency_fingerprint


SCHEMA_VERSION = 2
BASELINE_KIND = "dependency-normalized-merge-base"
TOOLCHAIN_COMPATIBILITY_PATCHES = ("async-021-fd-kind-symbol",)
_RUN_CONTEXT: dict[str, object] = {}


class CommandFailure(RuntimeError):
    def __init__(
        self,
        command: list[str],
        returncode: int,
        stdout: str,
        stderr: str,
    ) -> None:
        self.command = command
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr
        detail = "\n".join(
            section
            for section in (
                f"stdout:\n{stdout.strip()}" if stdout.strip() else "",
                f"stderr:\n{stderr.strip()}" if stderr.strip() else "",
            )
            if section
        ) or "no output"
        super().__init__(f"command failed ({returncode}): {' '.join(command)}: {detail}")


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    records: list[dict[str, object]] | None = None,
    phase: str = "command",
) -> str:
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    if records is not None:
        records.append(
            {
                "phase": phase,
                "command": command,
                "cwd": str(cwd) if cwd is not None else None,
                "returncode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            }
        )
    if result.returncode != 0:
        raise CommandFailure(command, result.returncode, result.stdout, result.stderr)
    return (result.stdout + result.stderr).strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_native_asset(
    repo: Path,
    native: Path,
    platform_name: str,
    *,
    environment: dict[str, str],
    records: list[dict[str, object]] | None = None,
    phase: str = "baseline-normalize-native",
) -> None:
    """Apply the same platform normalization used by candidate releases.

    Windows PE/COFF timestamps are produced by the linker, so a
    dependency-normalized baseline must pass through the exact same
    normalizer before either repeatability or size evidence is computed.
    """
    if not platform_name.startswith("windows-"):
        return
    run(
        [
            "python3",
            str(repo / "tools/release/normalize_pe_timestamp.py"),
            str(native),
        ],
        env=environment,
        records=records,
        phase=phase,
    )


def load_artifact_size(repo: Path):
    path = repo / "tools/release/check_artifact_size.py"
    spec = importlib.util.spec_from_file_location("moonjust_artifact_size", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load artifact analyzer: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def extract_commit(repo: Path, commit: str, destination: Path) -> None:
    archive = subprocess.run(
        ["git", "-C", str(repo), "archive", commit],
        check=True,
        capture_output=True,
    ).stdout
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as source:
        # Python 3.14 warns about the legacy unrestricted extraction API.
        # Git's archive contains only repository paths, so use the standard
        # data filter where available while retaining the older-runtime path.
        if sys.version_info >= (3, 12):
            source.extractall(destination, filter="data")
        else:
            source.extractall(destination)


def stage_archive(
    repo: Path,
    source: Path,
    native: Path,
    platform_name: str,
    output: Path,
    *,
    records: list[dict[str, object]] | None = None,
) -> None:
    stage = output.parent / "stage"
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    native_name = "just.exe" if platform_name.startswith("windows-") else "just"
    shutil.copy2(native, stage / native_name)
    os.chmod(stage / native_name, 0o755)
    for filename in ("LICENSE", "NOTICE", "README.mbt.md", "SECURITY.md", "CHANGELOG.md"):
        shutil.copy2(source / filename, stage / filename)
    run(
        [
            "python3",
            str(repo / "tools/release/create_archive.py"),
            "--source",
            str(stage),
            "--output",
            str(output),
        ],
        records=records,
        phase="archive-build",
    )


def apply_toolchain_compatibility_patches(work: Path) -> list[dict[str, object]]:
    """Apply explicit, auditable shims for removed async ABI symbols.

    The patch is only applied to the temporary extracted merge-base tree. It
    does not modify the candidate tree or any third-party registry source.
    """
    process_candidates = (
        work / "src/host_process/process.mbt",
        work / "internal/host_process/process.mbt",
    )
    process = next((path for path in process_candidates if path.is_file()), None)
    if process is None:
        return []
    source = process.read_text(encoding="utf-8")
    if "moonbitlang_async_kind_of_fd" not in source:
        return []

    c_candidates = (
        process.parent / "signal_forward.c",
        work / "internal/host_process/signal_forward.c",
    )
    c_source = next((path for path in c_candidates if path.is_file()), None)
    if c_source is None:
        raise RuntimeError(
            "async-021-fd-kind-symbol requires the merge-base signal_forward.c"
        )
    c_text = c_source.read_text(encoding="utf-8")
    if "moonbitlang_async_kind_of_fd" in c_text:
        return []
    shim = r'''

/* Compatibility shim for the async 0.20 fd-kind symbol. The merge-base
 * process adapter is normalized to async 0.21, which no longer exports this
 * private helper. Keep this patch local to the extracted baseline tree. */
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#endif
MOONBIT_FFI_EXPORT
#ifdef _WIN32
int32_t moonbitlang_async_kind_of_fd(HANDLE handle) {
  return GetFileType(handle) == FILE_TYPE_DISK;
}
#else
int32_t moonbitlang_async_kind_of_fd(int32_t fd) {
  struct stat info;
  return fstat(fd, &info) == 0 && S_ISREG(info.st_mode);
}
#endif
'''
    c_source.write_text(c_text.rstrip() + shim, encoding="utf-8")
    return [
        {
            "id": "async-021-fd-kind-symbol",
            "file": str(c_source.relative_to(work)),
            "reason": (
                "merge-base process adapter references the private async 0.20 "
                "fd-kind symbol removed in async 0.21"
            ),
        }
    ]


def baseline_work_path(repo: Path, platform_name: str) -> Path:
    if not platform_name or any(
        not (character.isalnum() or character in "-_")
        for character in platform_name
    ):
        raise ValueError(f"invalid baseline platform: {platform_name!r}")
    return repo / "_build/dependency-normalized-baseline" / platform_name


def failure_classification(
    error: BaseException,
    command_records: list[dict[str, object]],
) -> str:
    failure_text = str(error)
    if isinstance(error, CommandFailure) and any(
        str(record.get("phase", "")).startswith("baseline-build")
        for record in command_records
    ):
        return "baseline-build-failed"
    if "Invalid lexscan target" in failure_text or "lexscan" in failure_text:
        return "baseline-build-failed"
    return "infrastructure-invalid"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--base-ref", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    output = args.output.resolve()
    _RUN_CONTEXT.clear()
    _RUN_CONTEXT.update(
        {
            "output": output,
            "platform": args.platform,
            "base_ref": args.base_ref,
            "repo": str(repo),
        }
    )
    commands: list[dict[str, object]] = []
    _RUN_CONTEXT["commands"] = commands
    candidate_commit = run(["git", "-C", str(repo), "rev-parse", "HEAD"], records=commands)
    _RUN_CONTEXT["candidate_commit"] = candidate_commit
    commit = run(
        ["git", "-C", str(repo), "rev-parse", args.base_ref],
        records=commands,
    )
    _RUN_CONTEXT["source_commit"] = commit
    dependency_records = dependency_fingerprint.latest_dependency_records(repo / "moon.mod")
    dependency_fingerprint.assert_declares_dependency_set(repo / "moon.mod", dependency_records)
    dependency_hash = dependency_fingerprint.dependency_fingerprint(dependency_records)
    _RUN_CONTEXT["dependency_set"] = dependency_records
    _RUN_CONTEXT["dependency_fingerprint"] = dependency_hash
    _RUN_CONTEXT["toolchain_compatibility_patches"] = []
    base_record: dict[str, object] = {
        "schema_version": SCHEMA_VERSION,
        "kind": BASELINE_KIND,
        "status": "running",
        "comparable_assets": False,
        "source_commit": commit,
        "candidate_commit": candidate_commit,
        "platform": args.platform,
        "moon": run(["moon", "version", "--all"], records=commands),
        "moon_tree": run(["moon", "tree"], cwd=repo, records=commands),
        "dependency_set": dependency_records,
        "dependency_fingerprint": dependency_hash,
        "toolchain_compatibility_patches": [],
        "commands": commands,
    }
    work = baseline_work_path(repo, args.platform)
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    try:
        extract_commit(repo, commit, work)
        dependency_fingerprint.normalize_direct_dependencies(work / "moon.mod", dependency_records)
        compatibility_patches = apply_toolchain_compatibility_patches(work)
        unknown_patches = sorted(
            str(patch.get("id"))
            for patch in compatibility_patches
            if patch.get("id") not in TOOLCHAIN_COMPATIBILITY_PATCHES
        )
        if unknown_patches:
            raise RuntimeError(
                "unregistered baseline compatibility patches: "
                + ", ".join(unknown_patches)
            )
        _RUN_CONTEXT["toolchain_compatibility_patches"] = compatibility_patches
        base_record["toolchain_compatibility_patches"] = compatibility_patches
        environment = os.environ.copy()
        environment.update({"MOON_DEP_CACHE": "off", "MOON_BUILD_CACHE": "off"})
        environment.setdefault("SOURCE_DATE_EPOCH", "0")
        environment.setdefault("ZERO_AR_DATE", "1")
        # Resolve the normalized merge-base from this run's dependency set.
        run(["moon", "-C", str(work), "update"], env=environment, records=commands, phase="dependency-update")
        run(["moon", "-C", str(work), "install"], env=environment, records=commands, phase="dependency-install")
        base_record["normalized_moon_tree"] = run(
            ["moon", "tree"], cwd=work, env=environment, records=commands,
            phase="normalized-moon-tree",
        )
        native_dir = work / "_build/native"
        wasm_dir = work / "_build/wasm"
        run(
            [
                "moon",
                "-C",
                str(work),
                "build",
                "--frozen",
                "--release",
                "--strip",
                "--target",
                "native",
                "--target-dir",
                str(native_dir),
                "cmd/just",
            ],
            env=environment,
            records=commands,
            phase="baseline-build-native",
        )
        run(
            [
                "moon",
                "-C",
                str(work),
                "build",
                "--frozen",
                "--release",
                "--strip",
                "--target",
                "wasm",
                "--target-dir",
                str(wasm_dir),
                "cmd/just",
            ],
            env=environment,
            records=commands,
            phase="baseline-build-wasm",
        )
        native = native_dir / "native/release/build/cmd/just/just.exe"
        wasm = wasm_dir / "wasm/release/build/cmd/just/just.wasm"
        if not native.is_file() or not wasm.is_file():
            raise RuntimeError("merge-base release artifacts are missing")
        normalize_native_asset(
            repo,
            native,
            args.platform,
            environment=environment,
            records=commands,
            phase="baseline-normalize-native",
        )
        archive_suffix = ".zip" if args.platform.startswith("windows-") else ".tar.gz"
        archive = work / f"moonjust-baseline{archive_suffix}"
        stage_archive(repo, work, native, args.platform, archive, records=commands)
        first_hashes = {
            "native": sha256(native),
            "wasm1": sha256(wasm),
            "archive": sha256(archive),
        }
        shutil.rmtree(native_dir)
        shutil.rmtree(wasm_dir)
        archive.unlink()
        run(
            [
                "moon",
                "-C",
                str(work),
                "build",
                "--frozen",
                "--release",
                "--strip",
                "--target",
                "native",
                "--target-dir",
                str(native_dir),
                "cmd/just",
            ],
            env=environment,
            records=commands,
            phase="baseline-build-repeat-native",
        )
        normalize_native_asset(
            repo,
            native,
            args.platform,
            environment=environment,
            records=commands,
            phase="baseline-normalize-repeat-native",
        )
        run(
            [
                "moon",
                "-C",
                str(work),
                "build",
                "--frozen",
                "--release",
                "--strip",
                "--target",
                "wasm",
                "--target-dir",
                str(wasm_dir),
                "cmd/just",
            ],
            env=environment,
            records=commands,
            phase="baseline-build-repeat-wasm",
        )
        stage_archive(repo, work, native, args.platform, archive, records=commands)
        second_hashes = {
            "native": sha256(native),
            "wasm1": sha256(wasm),
            "archive": sha256(archive),
        }
        if first_hashes != second_hashes:
            raise RuntimeError(
                "dependency-normalized merge-base is not reproducible: "
                + json.dumps(
                    {"first": first_hashes, "second": second_hashes},
                    sort_keys=True,
                )
            )
        analyzer = load_artifact_size(repo)
        record = dict(base_record)
        record.update(
            {
                "status": "passed",
                "comparable_assets": True,
                "repeatability": {
                    "status": "passed",
                    "first_sha256": first_hashes,
                    "second_sha256": second_hashes,
                },
                "native": analyzer.artifact_record(native, analyze=True),
                "wasm1": analyzer.artifact_record(wasm, analyze=True),
                "archive": analyzer.artifact_record(archive),
            }
        )
        for name in ("native", "wasm1", "archive"):
            record[name]["path"] = f"merge-base/{name}"
    finally:
        if work.exists():
            shutil.rmtree(work)
    record["commands"] = commands
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"dependency-normalized merge-base size baseline: {output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, tarfile.TarError, json.JSONDecodeError) as error:
        output = _RUN_CONTEXT.get("output")
        if isinstance(output, Path):
            command_records = [
                record
                for record in _RUN_CONTEXT.get("commands", [])
                if isinstance(record, dict)
            ]
            failure_class = failure_classification(error, command_records)
            failure_record = {
                "schema_version": SCHEMA_VERSION,
                "kind": BASELINE_KIND,
                "status": "infrastructure-invalid",
                "failure_class": failure_class,
                "failure": str(error),
                "comparable_assets": False,
                "source_commit": _RUN_CONTEXT.get("source_commit"),
                "candidate_commit": _RUN_CONTEXT.get("candidate_commit"),
                "base_ref": _RUN_CONTEXT.get("base_ref"),
                "platform": _RUN_CONTEXT.get("platform"),
                "dependency_set": _RUN_CONTEXT.get("dependency_set", []),
                "dependency_fingerprint": _RUN_CONTEXT.get("dependency_fingerprint"),
                "toolchain_compatibility_patches": _RUN_CONTEXT.get(
                    "toolchain_compatibility_patches", []
                ),
                "commands": _RUN_CONTEXT.get("commands", []),
            }
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(failure_record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            print(f"dependency-normalized merge-base baseline unavailable: {output}")
        raise SystemExit(f"size baseline error: {error}")
