#!/usr/bin/env python3
"""Enforce the frozen 5% release-artifact size budget."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def detected_platform() -> str:
    systems = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}
    machines = {
        "x86_64": "x86_64",
        "AMD64": "x86_64",
        "arm64": "aarch64",
        "aarch64": "aarch64",
    }
    system = systems.get(platform.system())
    machine = machines.get(platform.machine())
    if system is None or machine is None:
        raise ValueError(
            f"unsupported artifact-size platform: {platform.system()}-{platform.machine()}"
        )
    return f"{system}-{machine}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--wasm", type=Path, required=True)
    parser.add_argument("--platform", default=detected_platform())
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text())
    if baseline.get("schema_version") != 1:
        raise ValueError("unsupported artifact-size baseline schema")
    native_baseline = baseline.get("native", {}).get(args.platform)
    if native_baseline is None:
        raise ValueError(
            f"frozen native artifact baseline is missing for {args.platform}"
        )
    wasm_baseline = baseline.get("wasm1")
    if not isinstance(wasm_baseline, dict):
        raise ValueError("frozen wasm1 artifact baseline is missing")
    for path in (args.native, args.wasm):
        if not path.is_file():
            raise ValueError(f"release artifact is missing: {path}")
    record = {
        "schema_version": 1,
        "platform": args.platform,
        "baseline_commit": baseline["commit"],
        "native": {
            "bytes": args.native.stat().st_size,
            "sha256": sha256(args.native),
            "baseline_bytes": native_baseline["bytes"],
        },
        "wasm1": {
            "bytes": args.wasm.stat().st_size,
            "sha256": sha256(args.wasm),
            "baseline_bytes": wasm_baseline["bytes"],
        },
    }
    failures = []
    for name in ("native", "wasm1"):
        values = record[name]
        values["ratio"] = values["bytes"] / values["baseline_bytes"]
        if values["ratio"] > 1.05:
            failures.append(
                f"{name} grew {(values['ratio'] - 1) * 100:.2f}% from frozen baseline"
            )
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
    if failures:
        raise ValueError("; ".join(failures))
    print(
        "artifact size gate passed: "
        f"native={record['native']['ratio']:.3f}x "
        f"wasm1={record['wasm1']['ratio']:.3f}x"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"artifact size gate error: {error}")
