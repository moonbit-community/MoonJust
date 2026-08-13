#!/usr/bin/env python3
import argparse
import hashlib
import pathlib
import shutil
import stat
import subprocess
import tarfile
import tempfile
import zipfile


def fail(message: str) -> None:
    raise SystemExit(f"Phase 11 upgrade rehearsal error: {message}")


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract_executable(archive: pathlib.Path, target: pathlib.Path) -> pathlib.Path:
    expected = "just.exe" if archive.suffix == ".zip" else "just"
    if archive.suffix == ".zip":
        with zipfile.ZipFile(archive) as stream:
            names = [item.filename for item in stream.infolist() if not item.is_dir()]
            if expected not in names:
                fail(f"{archive.name} does not contain {expected}")
            target.write_bytes(stream.read(expected))
    else:
        with tarfile.open(archive, "r:gz") as stream:
            item = stream.getmember(expected)
            source = stream.extractfile(item)
            if source is None:
                fail(f"{archive.name} does not contain readable {expected}")
            target.write_bytes(source.read())
    target.chmod(target.stat().st_mode | stat.S_IXUSR)
    return target


def smoke(executable: pathlib.Path, repo: pathlib.Path) -> tuple[str, str, str, str]:
    version = subprocess.run(
        [str(executable), "--version"], text=True, capture_output=True, timeout=30
    )
    if version.returncode != 0 or not version.stdout.startswith("moonjust "):
        fail("version smoke failed")
    query = subprocess.run(
        [
            str(executable),
            "--list",
            "--justfile",
            str(repo / "tests/fixtures/phase-6/justfile"),
        ],
        text=True,
        capture_output=True,
        timeout=30,
    )
    if query.returncode != 0 or "hello" not in query.stdout:
        fail("query corpus failed")
    execution = subprocess.run(
        [
            str(executable),
            "--justfile",
            str(repo / "tests/fixtures/phase-8/line.justfile"),
            "build",
        ],
        text=True,
        capture_output=True,
        timeout=30,
    )
    if (
        execution.returncode != 0
        or execution.stdout != "hello world\nhidden\n"
        or execution.stderr != "echo hello world\nfalse\n"
    ):
        fail("execution corpus failed")
    return query.stdout, query.stderr, execution.stdout, execution.stderr


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--previous", type=pathlib.Path, required=True)
    parser.add_argument("--candidate", type=pathlib.Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="moonjust-upgrade-") as raw:
        root = pathlib.Path(raw)
        installed = root / ("just.exe" if args.candidate.suffix == ".zip" else "just")
        previous = extract_executable(args.previous, root / "previous")
        candidate = extract_executable(args.candidate, root / "candidate")
        previous_digest = digest(previous)
        candidate_digest = digest(candidate)
        if previous_digest == candidate_digest:
            fail("previous and candidate archives contain identical executable bytes")

        shutil.copy2(previous, installed)
        previous_corpus = smoke(installed, args.repo)
        rollback = root / "rollback"
        shutil.copy2(installed, rollback)

        shutil.copy2(candidate, installed)
        candidate_corpus = smoke(installed, args.repo)
        if candidate_corpus != previous_corpus:
            fail("candidate query/execution corpus differs from previous release")
        if digest(installed) != candidate_digest:
            fail("candidate replacement changed bytes")

        shutil.copy2(rollback, installed)
        rollback_corpus = smoke(installed, args.repo)
        if rollback_corpus != previous_corpus:
            fail("rollback query/execution corpus differs from previous release")
        if digest(installed) != previous_digest:
            fail("rollback did not restore the exact previous bytes")
    print("Phase 11 upgrade rehearsal verified: previous, candidate, corpus and exact rollback")


if __name__ == "__main__":
    main()
