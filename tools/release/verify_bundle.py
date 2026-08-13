#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import zipfile


EXPECTED_SUPPORT = {
    "LICENSE",
    "NOTICE",
    "README.mbt.md",
    "SECURITY.md",
    "CHANGELOG.md",
    "SHA256SUMS",
    "sbom.cdx.json",
    "provenance.intoto.json",
}


def fail(message: str) -> None:
    raise SystemExit(f"Phase 11 bundle error: {message}")


def safe_names(names: list[str]) -> None:
    if len(names) != len(set(names)):
        fail("archive contains duplicate entries")
    for raw in names:
        path = pathlib.PurePosixPath(raw)
        if (
            path.is_absolute()
            or pathlib.PureWindowsPath(raw).drive
            or ".." in path.parts
            or "\\" in raw
        ):
            fail(f"unsafe archive entry: {raw}")


def extract(archive: pathlib.Path, target: pathlib.Path) -> None:
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as stream:
            members = stream.infolist()
            safe_names([item.filename for item in members])
            for item in members:
                mode = item.external_attr >> 16
                kind = stat.S_IFMT(mode)
                if item.is_dir():
                    continue
                if kind not in {0, stat.S_IFREG}:
                    fail(f"unsupported archive entry: {item.filename}")
                output = target / item.filename
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(stream.read(item))
                if mode:
                    output.chmod(stat.S_IMODE(mode))
    else:
        with tarfile.open(archive, "r:gz") as stream:
            members = stream.getmembers()
            safe_names([item.name for item in members])
            if any(not item.isfile() and not item.isdir() for item in members):
                fail("archive contains unsupported non-regular entries")
            for item in (member for member in members if member.isfile()):
                output = target / item.name
                output.parent.mkdir(parents=True, exist_ok=True)
                source = stream.extractfile(item)
                if source is None:
                    fail(f"cannot read archive entry: {item.name}")
                output.write_bytes(source.read())
                output.chmod(item.mode)


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def module_field(repo: pathlib.Path, name: str) -> str:
    pattern = re.compile(rf'^\s*{re.escape(name)}\s*=\s*"([^"]+)"\s*$')
    values = [
        match.group(1)
        for line in (repo / "moon.mod").read_text().splitlines()
        if (match := pattern.match(line))
    ]
    if len(values) != 1:
        fail(f"moon.mod field {name!r} is missing or repeated")
    return values[0]


def checksum(path: pathlib.Path, expected_name: str) -> str:
    if not path.is_file():
        fail(f"checksum sidecar is missing: {path.name}")
    match = re.fullmatch(r"([0-9a-f]{64})  ([^\r\n]+)\n?", path.read_text())
    if match is None or match.group(2) != expected_name:
        fail(f"checksum sidecar is malformed: {path.name}")
    return match.group(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--archive", type=pathlib.Path, required=True)
    parser.add_argument("--platform", required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    archive = args.archive.resolve()
    version = module_field(repo, "version")
    extension = ".zip" if args.platform.startswith("windows-") else ".tar.gz"
    expected_archive_name = f"moonjust-{version}-{args.platform}{extension}"
    if archive.name != expected_archive_name:
        fail(f"archive name differs: expected {expected_archive_name}")
    archive_digest = sha256(archive)
    if checksum(pathlib.Path(f"{archive}.sha256"), archive.name) != archive_digest:
        fail("external archive checksum differs")

    build_record_path = archive.parent / f"build-{args.platform}.json"
    if not build_record_path.is_file():
        fail("build record is missing")
    build_record = json.loads(build_record_path.read_text())
    expected_commit = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    expected_record = {
        "schema_version": 1,
        "version": version,
        "commit": expected_commit,
        "platform": args.platform,
        "archive": archive.name,
        "archive_sha256": archive_digest,
        "wasm_asset": f"assets/moonbit-community/MoonJust@{version}/cmd/just/just.wasm",
    }
    if build_record != expected_record:
        fail("build record differs from repository and artifacts")
    wasm = archive.parent / expected_record["wasm_asset"]
    if not wasm.is_file():
        fail("wasm asset is missing")
    if checksum(pathlib.Path(f"{wasm}.sha256"), wasm.name) != sha256(wasm):
        fail("wasm asset checksum differs")

    with tempfile.TemporaryDirectory(prefix="moonjust-bundle-") as raw:
        root = pathlib.Path(raw)
        extract(archive, root)
        executable_name = "just.exe" if args.platform.startswith("windows-") else "just"
        expected = EXPECTED_SUPPORT | {executable_name}
        actual = {path.name for path in root.iterdir() if path.is_file()}
        if actual != expected:
            fail(f"bundle entries differ: expected {sorted(expected)}, got {sorted(actual)}")
        executable = root / executable_name
        if not args.platform.startswith("windows-"):
            executable.chmod(executable.stat().st_mode | stat.S_IXUSR)
        sums = {}
        for line in (root / "SHA256SUMS").read_text().splitlines():
            digest_value, name = line.split(None, 1)
            sums[name.strip()] = digest_value
        if sums != {executable_name: sha256(executable)}:
            fail("embedded checksum manifest differs")
        subprocess.run(
            [
                "python3",
                str(repo / "tools/release/verify_supply_chain.py"),
                "--repo",
                str(repo),
                "--artifact",
                str(executable),
                "--target",
                args.platform,
                "--sbom",
                str(root / "sbom.cdx.json"),
                "--provenance",
                str(root / "provenance.intoto.json"),
            ],
            check=True,
        )
        if args.platform.startswith("windows-") and shutil.which("cmd") is None:
            print("Phase 11 bundle verified structurally; Windows execution deferred to Windows runner")
            return
        result = subprocess.run([str(executable), "--version"], text=True, capture_output=True)
        if result.returncode != 0 or not result.stdout.startswith(f"moonjust {version} "):
            fail("extracted executable version smoke failed")
        print(f"Phase 11 bundle verified and executed: {args.platform}")


if __name__ == "__main__":
    main()
