#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(archive: pathlib.Path, target: pathlib.Path) -> None:
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as stream:
            stream.extractall(target)
    else:
        with tarfile.open(archive, "r:gz") as stream:
            stream.extractall(target, filter="data")


def prepare(source: pathlib.Path, target: pathlib.Path, platform: str) -> pathlib.Path:
    target.mkdir(parents=True)
    archive = target / source.name
    shutil.copy2(source, archive)
    shutil.copy2(pathlib.Path(f"{source}.sha256"), pathlib.Path(f"{archive}.sha256"))
    shutil.copy2(source.parent / f"build-{platform}.json", target)
    shutil.copytree(source.parent / "assets", target / "assets")
    return archive


def bind_archive(archive: pathlib.Path, platform: str) -> None:
    archive_digest = digest(archive)
    pathlib.Path(f"{archive}.sha256").write_text(
        f"{archive_digest}  {archive.name}\n"
    )
    record = archive.parent / f"build-{platform}.json"
    data = json.loads(record.read_text())
    data["archive_sha256"] = archive_digest
    record.write_text(json.dumps(data, indent=2) + "\n")


def expect_rejected(
    repo: pathlib.Path, archive: pathlib.Path, platform: str, reason: str
) -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(repo / "tools/release/verify_bundle.py"),
            "--repo",
            str(repo),
            "--archive",
            str(archive),
            "--platform",
            platform,
        ],
        text=True,
        capture_output=True,
    )
    if result.returncode == 0:
        raise SystemExit(f"Phase 11 tamper test accepted {reason}")


def repack(repo: pathlib.Path, archive: pathlib.Path, mutate) -> None:
    with tempfile.TemporaryDirectory(prefix="moonjust-tamper-stage-") as raw:
        stage = pathlib.Path(raw)
        extract(archive, stage)
        mutate(stage)
        subprocess.run(
            [
                sys.executable,
                str(repo / "tools/release/create_archive.py"),
                "--source",
                str(stage),
                "--output",
                str(archive),
            ],
            check=True,
        )


def add_unsafe_entry(archive: pathlib.Path) -> None:
    temporary = archive.with_name(f"unsafe-{archive.name}")
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as source, zipfile.ZipFile(
            temporary, "w", zipfile.ZIP_DEFLATED
        ) as output:
            for item in source.infolist():
                output.writestr(item, source.read(item.filename))
            output.writestr("../escape", b"escape")
    else:
        with tarfile.open(archive, "r:gz") as source, tarfile.open(
            temporary, "w:gz"
        ) as output:
            for item in source.getmembers():
                stream = source.extractfile(item) if item.isfile() else None
                output.addfile(item, stream)
            entry = tarfile.TarInfo("../escape")
            entry.size = len(b"escape")
            import io

            output.addfile(entry, io.BytesIO(b"escape"))
    temporary.replace(archive)


def add_symlink_entry(archive: pathlib.Path) -> None:
    temporary = archive.with_name(f"symlink-{archive.name}")
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as source, zipfile.ZipFile(
            temporary, "w", zipfile.ZIP_DEFLATED
        ) as output:
            for item in source.infolist():
                output.writestr(item, source.read(item.filename))
            entry = zipfile.ZipInfo("link")
            entry.create_system = 3
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            output.writestr(entry, "just")
    else:
        with tarfile.open(archive, "r:gz") as source, tarfile.open(
            temporary, "w:gz"
        ) as output:
            for item in source.getmembers():
                stream = source.extractfile(item) if item.isfile() else None
                output.addfile(item, stream)
            entry = tarfile.TarInfo("link")
            entry.type = tarfile.SYMTYPE
            entry.linkname = "just"
            output.addfile(entry)
    temporary.replace(archive)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--archive", type=pathlib.Path, required=True)
    parser.add_argument("--platform", required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    source = args.archive.resolve()

    with tempfile.TemporaryDirectory(prefix="moonjust-tamper-") as raw:
        root = pathlib.Path(raw)

        archive = prepare(source, root / "archive-checksum", args.platform)
        pathlib.Path(f"{archive}.sha256").write_text(f"{'0' * 64}  {archive.name}\n")
        expect_rejected(repo, archive, args.platform, "archive checksum tampering")

        archive = prepare(source, root / "build-record", args.platform)
        record = archive.parent / f"build-{args.platform}.json"
        data = json.loads(record.read_text())
        data["commit"] = "0" * 40
        record.write_text(json.dumps(data) + "\n")
        expect_rejected(repo, archive, args.platform, "build-record tampering")

        archive = prepare(source, root / "wasm-checksum", args.platform)
        sidecar = next((archive.parent / "assets").rglob("just.wasm.sha256"))
        sidecar.write_text(f"{'0' * 64}  just.wasm\n")
        expect_rejected(repo, archive, args.platform, "wasm checksum tampering")

        archive = prepare(source, root / "unsafe-path", args.platform)
        add_unsafe_entry(archive)
        bind_archive(archive, args.platform)
        expect_rejected(repo, archive, args.platform, "parent path traversal")

        archive = prepare(source, root / "symlink", args.platform)
        add_symlink_entry(archive)
        bind_archive(archive, args.platform)
        expect_rejected(repo, archive, args.platform, "symbolic-link entry")

        archive = prepare(source, root / "provenance", args.platform)
        def mutate_provenance(stage: pathlib.Path) -> None:
            path = stage / "provenance.intoto.json"
            data = json.loads(path.read_text())
            data["predicate"]["buildDefinition"]["resolvedDependencies"][0][
                "digest"
            ]["gitCommit"] = "0" * 40
            path.write_text(json.dumps(data) + "\n")
        repack(repo, archive, mutate_provenance)
        bind_archive(archive, args.platform)
        expect_rejected(repo, archive, args.platform, "provenance tampering")

        archive = prepare(source, root / "sbom", args.platform)
        def mutate_sbom(stage: pathlib.Path) -> None:
            path = stage / "sbom.cdx.json"
            data = json.loads(path.read_text())
            data["components"] = []
            path.write_text(json.dumps(data) + "\n")
        repack(repo, archive, mutate_sbom)
        bind_archive(archive, args.platform)
        expect_rejected(repo, archive, args.platform, "SBOM tampering")

    print("Phase 11 tamper resistance verified: checksums, build record, paths, links, provenance and SBOM")


if __name__ == "__main__":
    main()
