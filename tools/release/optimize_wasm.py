#!/usr/bin/env python3
"""Apply the pinned post-link optimizer to a MoonJust wasm1 artifact."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import subprocess
import tarfile
import tempfile
import urllib.request
from pathlib import Path


BINARYEN_VERSION = "132"
BINARYEN_TAG = f"version_{BINARYEN_VERSION}"
BINARYEN_DIRECTORY = f"binaryen-version_{BINARYEN_VERSION}"
BINARYEN_RELEASE = (
    f"https://github.com/WebAssembly/binaryen/releases/download/{BINARYEN_TAG}"
)
OPTIMIZER_ARGUMENTS = (
    "--enable-simd",
    "--enable-bulk-memory",
    "--enable-bulk-memory-opt",
    "--enable-reference-types",
    "--enable-multivalue",
    "--enable-nontrapping-float-to-int",
    "-O2",
)
ARCHIVES = {
    ("Linux", "x86_64"): (
        "binaryen-version_132-x86_64-linux.tar.gz",
        "195ddc94f9bc89f45abdabb0b9eea86023d727ba90eac8b35b80f2544fc30572",
    ),
    ("Darwin", "arm64"): (
        "binaryen-version_132-arm64-macos.tar.gz",
        "98aad827847af7ef990ed7098d885725c8e5b5aae75073403635617ae4e259aa",
    ),
    ("Windows", "x86_64"): (
        "binaryen-version_132-x86_64-windows.tar.gz",
        "2089428ec98c899b45ee5d00636ddd6e2da8636cc473ef50b165cc25793ef7cb",
    ),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalized_machine(value: str) -> str:
    return {
        "AMD64": "x86_64",
        "amd64": "x86_64",
        "aarch64": "arm64",
    }.get(value, value)


def archive_spec(system: str, machine: str) -> tuple[str, str]:
    key = (system, normalized_machine(machine))
    try:
        return ARCHIVES[key]
    except KeyError as error:
        raise RuntimeError(
            f"Binaryen {BINARYEN_VERSION} is unavailable for {key[0]}-{key[1]}"
        ) from error


def optimizer_metadata_path(artifact: Path) -> Path:
    return artifact.with_name(artifact.name + ".optimizer.json")


def read_optimizer_metadata(artifact: Path) -> dict[str, object]:
    sidecar = optimizer_metadata_path(artifact)
    try:
        value = json.loads(sidecar.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"invalid wasm optimizer metadata {sidecar}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"wasm optimizer metadata is not an object: {sidecar}")
    if value.get("optimizer_version") != f"wasm-opt version {BINARYEN_VERSION} ({BINARYEN_TAG})":
        raise RuntimeError(f"wasm optimizer version is not pinned: {sidecar}")
    arguments = value.get("arguments")
    if arguments != list(OPTIMIZER_ARGUMENTS):
        raise RuntimeError(f"wasm optimizer arguments differ from the release profile: {sidecar}")
    if value.get("output_sha256") != sha256(artifact):
        raise RuntimeError(f"wasm optimizer output hash differs: {sidecar}")
    return value


def verify_optimizer(path: Path) -> str:
    result = subprocess.run(
        [str(path), "--version"],
        check=True,
        capture_output=True,
        text=True,
    )
    version = (result.stdout + result.stderr).strip()
    expected = f"wasm-opt version {BINARYEN_VERSION} ({BINARYEN_TAG})"
    if version != expected:
        raise RuntimeError(f"unexpected wasm-opt version: {version!r}, expected {expected!r}")
    return version


def safe_extract(archive: Path, destination: Path) -> None:
    root = destination.resolve()
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle.getmembers():
            target = (destination / member.name).resolve()
            if target != root and root not in target.parents:
                raise RuntimeError(f"Binaryen archive escapes extraction root: {member.name}")
            if member.issym() or member.islnk():
                raise RuntimeError(f"Binaryen archive contains a link: {member.name}")
            if not member.isfile() and not member.isdir():
                raise RuntimeError(f"Binaryen archive contains a special file: {member.name}")
        bundle.extractall(destination)


def download_optimizer(cache: Path) -> Path:
    archive_name, expected_digest = archive_spec(platform.system(), platform.machine())
    executable = "wasm-opt.exe" if platform.system() == "Windows" else "wasm-opt"
    tool = cache / BINARYEN_DIRECTORY / "bin" / executable
    if tool.is_file():
        verify_optimizer(tool)
        return tool
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / archive_name
    if not archive.is_file() or sha256(archive) != expected_digest:
        request = urllib.request.Request(
            f"{BINARYEN_RELEASE}/{archive_name}",
            headers={"User-Agent": "MoonJust-release-builder"},
        )
        with urllib.request.urlopen(request, timeout=120) as response:
            with tempfile.NamedTemporaryFile(dir=cache, delete=False) as stream:
                temporary = Path(stream.name)
                while chunk := response.read(1024 * 1024):
                    stream.write(chunk)
        try:
            if sha256(temporary) != expected_digest:
                raise RuntimeError(f"Binaryen archive checksum mismatch: {archive_name}")
            os.replace(temporary, archive)
        finally:
            temporary.unlink(missing_ok=True)
    safe_extract(archive, cache)
    if not tool.is_file():
        raise RuntimeError(f"Binaryen archive did not contain {tool}")
    verify_optimizer(tool)
    return tool


def optimize(
    source: Path,
    output: Path,
    *,
    cache: Path,
    wasm_opt: Path | None = None,
) -> dict[str, object]:
    source = source.resolve()
    output = output.resolve()
    if not source.is_file():
        raise RuntimeError(f"wasm input is missing: {source}")
    tool = wasm_opt.resolve() if wasm_opt is not None else download_optimizer(cache)
    version = verify_optimizer(tool)
    input_digest = sha256(source)
    input_bytes = source.stat().st_size
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as stream:
        temporary = Path(stream.name)
    try:
        subprocess.run(
            [str(tool), str(source), *OPTIMIZER_ARGUMENTS, "-o", str(temporary)],
            check=True,
        )
        if not temporary.read_bytes().startswith(b"\0asm\x01\0\0\0"):
            raise RuntimeError("wasm-opt output is not a wasm1 module")
        temporary.chmod(source.stat().st_mode & 0o777)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    metadata: dict[str, object] = {
        "schema_version": 1,
        "optimizer": "wasm-opt",
        "optimizer_version": version,
        "optimizer_sha256": sha256(tool),
        "arguments": list(OPTIMIZER_ARGUMENTS),
        "input_bytes": input_bytes,
        "input_sha256": input_digest,
        "output_bytes": output.stat().st_size,
        "output_sha256": sha256(output),
    }
    optimizer_metadata_path(output).write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--cache", type=Path, default=Path("_build/tooling/binaryen"))
    parser.add_argument("--wasm-opt", type=Path)
    args = parser.parse_args()
    metadata = optimize(
        args.input,
        args.output or args.input,
        cache=args.cache.resolve(),
        wasm_opt=args.wasm_opt,
    )
    print(json.dumps(metadata, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError, tarfile.TarError) as error:
        raise SystemExit(f"wasm optimization error: {error}")
