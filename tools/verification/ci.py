#!/usr/bin/env python3
"""Small cross-platform helpers used by GitHub Actions workflow steps."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import re
import subprocess
import sys
from pathlib import Path


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def run(repo: Path, *argv: str, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(list(argv), cwd=repo, check=True, text=True, capture_output=capture)


def version(repo: Path) -> str:
    match = re.search(r'^version\s*=\s*"([^"]+)"$', (repo / "moon.mod").read_text(encoding="utf-8"), re.MULTILINE)
    if match is None:
        raise RuntimeError("moon.mod has no version")
    return match.group(1)


def shared_wasm(repo: Path, source: Path, debug: Path, repeat: Path, out: Path) -> int:
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, out / "just.wasm")
    shutil.copy2(debug, out / "just.debug.wasm")
    (out / "just.wasm.sha256").write_text(f"{digest(out / 'just.wasm')}  just.wasm\n", encoding="utf-8")
    run(repo, sys.executable, "tools/release/check_repeatable_artifacts.py", "--platform", "wasm1",
        "--pair", f"wasm1={out / 'just.wasm'}={repeat}", "--output", str(out / "repeatability.json"))
    return 0


def baseline_wasm(repo: Path, source: Path, repeat: Path, out: Path) -> int:
    out.mkdir(parents=True, exist_ok=True)
    source_hash = digest(source)
    repeat_hash = digest(repeat)
    if source_hash != repeat_hash:
        raise SystemExit("baseline wasm builds are not byte-identical")
    shutil.copy2(source, out / "just.wasm")
    shutil.copy2(repeat, out / "just.repeat.wasm")
    (out / "just.wasm.sha256").write_text(
        f"{source_hash}  just.wasm\n", encoding="utf-8"
    )
    commit = subprocess.run(
        ["git", "-C", str(repo.resolve()), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    (out / "repeatability.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "status": "passed",
                "commit": commit,
                "platform": "wasm1",
                "pairs": {
                    "wasm1": {
                        "bytes": source.stat().st_size,
                        "sha256": source_hash,
                    }
                },
                "failures": [],
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return 0


def verify_shared(asset: Path, sidecar: Path) -> int:
    fields = sidecar.read_text(encoding="utf-8").split()
    if fields != [digest(asset), "just.wasm"]:
        raise SystemExit("shared wasm1 checksum mismatch")
    return 0


def platform_release(repo: Path, target: str, wasm: Path, base_ref: str) -> int:
    out = repo / "_build" / "release"
    first = repo / "_build" / "repeat-first"
    if first.exists():
        shutil.rmtree(first)
    first.mkdir(parents=True)
    command = [sys.executable, "tools/release/build_artifacts.py", "--repo", str(repo), "--platform", target, "--wasm-asset", str(wasm)]
    archive = Path(run(repo, *command, capture=True).stdout.strip().splitlines()[-1])
    native = out / "build" / "native" / "release" / "build" / "cmd" / "just" / "just.exe"
    run(repo, sys.executable, "tools/release/verify_bundle.py", "--repo", str(repo), "--archive", str(archive), "--platform", target)
    shutil.copy2(archive, first / "archive")
    shutil.copy2(native, first / "native")
    archive = Path(run(repo, *command, capture=True).stdout.strip().splitlines()[-1])
    run(repo, sys.executable, "tools/release/verify_bundle.py", "--repo", str(repo), "--archive", str(archive), "--platform", target)
    run(repo, sys.executable, "tools/release/check_repeatable_artifacts.py", "--platform", target,
        "--pair", f"native={first / 'native'}={native}", "--pair", f"archive={first / 'archive'}={archive}",
        "--output", str(out / f"repeatability-{target}.json"))
    run(repo, sys.executable, "tools/release/check_moonx_asset.py", "--repo", str(repo), "--registry", str(out),
        "--coordinate", f"ZSeanYves/MoonJust/cmd/just@{version(repo)}")
    run(repo, sys.executable, "tools/release/build_size_baseline.py", "--repo", str(repo), "--base-ref", base_ref,
        "--platform", target, "--output", str(repo / "_build/size-baseline.json"))
    run(repo, "moon", "build", "--frozen", "--release", "--no-strip", "--target", "native", "--target-dir", str(repo / "_build/size-debug"), "cmd/just")
    run(repo, sys.executable, "tools/release/check_artifact_size.py", "--baseline-report", str(repo / "_build/size-baseline.json"),
        "--platform", target, "--native", str(native), "--wasm", str(wasm),
        "--native-debug", str(repo / "_build/size-debug/native/release/build/cmd/just/just.exe"),
        "--wasm-debug", str(repo / "_build/shared-wasm/just.debug.wasm"), "--archive", str(archive),
        "--require-complete-baseline", "--output", str(out / f"artifact-size-{target}.json"))
    return 0


def baseline_platform(
    source: Path,
    tool_root: Path,
    target: str,
    wasm: Path,
    baseline: Path,
    source_commit: str,
    output: Path,
) -> int:
    source = source.resolve()
    tool_root = tool_root.resolve()
    command = [
        sys.executable,
        str(tool_root / "tools/release/build_artifacts.py"),
        "--repo",
        str(source),
        "--platform",
        target,
        "--wasm-asset",
        str(wasm.resolve()),
    ]
    archive = Path(run(source, *command, capture=True).stdout.strip().splitlines()[-1])
    native = source / "_build/release/build/native/release/build/cmd/just/just.exe"
    native_debug_root = source / "_build/size-debug"
    run(
        source,
        "moon",
        "build",
        "--frozen",
        "--release",
        "--no-strip",
        "--target",
        "native",
        "--target-dir",
        str(native_debug_root),
        "cmd/just",
    )
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    run(
        source,
        sys.executable,
        str(tool_root / "tools/release/check_artifact_size.py"),
        "--baseline",
        str(baseline.resolve()),
        "--historical-baseline",
        "--platform",
        target,
        "--source-commit",
        source_commit,
        "--source-patch",
        str(tool_root / "tools/release/latest-moonbit-baseline.patch"),
        "--native",
        str(native),
        "--wasm",
        str(wasm.resolve()),
        "--native-debug",
        str(native_debug_root / "native/release/build/cmd/just/just.exe"),
        "--archive",
        str(archive),
        "--report-only",
        "--output",
        str(output),
    )
    return 0


def require_results(results: list[str]) -> int:
    failures = [result for result in results if result != "success"]
    if failures:
        raise SystemExit(f"required CI job did not succeed: {', '.join(failures)}")
    return 0


def verify_moonx(repo: Path, registry: Path) -> int:
    run(
        repo,
        sys.executable,
        "tools/release/check_moonx_asset.py",
        "--repo",
        str(repo),
        "--registry",
        str(registry),
        "--coordinate",
        f"ZSeanYves/MoonJust/cmd/just@{version(repo)}",
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    stage = sub.add_parser("stage-shared-wasm")
    stage.add_argument("--source", type=Path, required=True)
    stage.add_argument("--debug", type=Path, required=True)
    stage.add_argument("--repeat", type=Path, required=True)
    stage.add_argument("--out", type=Path, required=True)
    baseline_stage = sub.add_parser("stage-baseline-wasm")
    baseline_stage.add_argument("--repo", type=Path, default=Path.cwd())
    baseline_stage.add_argument("--source", type=Path, required=True)
    baseline_stage.add_argument("--repeat", type=Path, required=True)
    baseline_stage.add_argument("--out", type=Path, required=True)
    verify = sub.add_parser("verify-shared-wasm")
    verify.add_argument("--asset", type=Path, required=True)
    verify.add_argument("--sidecar", type=Path, required=True)
    release = sub.add_parser("platform-release")
    release.add_argument("--repo", type=Path, default=Path.cwd())
    release.add_argument("--platform", required=True)
    release.add_argument("--wasm", type=Path, required=True)
    release.add_argument("--base-ref", default="origin/main")
    baseline = sub.add_parser("baseline-platform")
    baseline.add_argument("--repo", type=Path, required=True)
    baseline.add_argument("--tools", type=Path, required=True)
    baseline.add_argument("--platform", required=True)
    baseline.add_argument("--wasm", type=Path, required=True)
    baseline.add_argument("--baseline", type=Path, required=True)
    baseline.add_argument("--source-commit", required=True)
    baseline.add_argument("--output", type=Path, required=True)
    require = sub.add_parser("require-results")
    require.add_argument("results", nargs="+")
    moonx = sub.add_parser("verify-moonx")
    moonx.add_argument("--repo", type=Path, default=Path.cwd())
    moonx.add_argument("--registry", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "stage-shared-wasm":
        return shared_wasm(Path.cwd(), args.source, args.debug, args.repeat, args.out)
    if args.command == "stage-baseline-wasm":
        return baseline_wasm(args.repo, args.source.resolve(), args.repeat.resolve(), args.out.resolve())
    if args.command == "verify-shared-wasm":
        return verify_shared(args.asset, args.sidecar)
    if args.command == "baseline-platform":
        return baseline_platform(
            args.repo,
            args.tools,
            args.platform,
            args.wasm,
            args.baseline,
            args.source_commit,
            args.output,
        )
    if args.command == "require-results":
        return require_results(args.results)
    if args.command == "verify-moonx":
        return verify_moonx(args.repo.resolve(), args.registry.resolve())
    return platform_release(args.repo.resolve(), args.platform, args.wasm.resolve(), args.base_ref)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.SubprocessError) as error:
        raise SystemExit(f"CI helper error: {error}")
