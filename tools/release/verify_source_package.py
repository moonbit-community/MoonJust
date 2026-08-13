#!/usr/bin/env python3
import argparse
import pathlib
import re
import stat
import zipfile


REQUIRED = {
    "LICENSE",
    "NOTICE",
    "README.mbt.md",
    "README.md",
    "SECURITY.md",
    "CHANGELOG.md",
    "API.mbt.md",
    "docs/API.md",
    "docs/RELEASE_POLICY.md",
    "policies/ci.toml",
    "policies/deny.toml",
    "policies/execute.toml",
    "policies/inspect.toml",
    "moon.mod",
    "moon.pkg",
    "cmd/just/moon.pkg",
    "cmd/just/pkg.generated.mbti",
    "pkg.generated.mbti",
}


def fail(message: str) -> None:
    raise SystemExit(f"Phase 11 source package error: {message}")


def field(text: str, name: str) -> str:
    values = re.findall(rf'^\s*{re.escape(name)}\s*=\s*"([^"]+)"\s*$', text, re.M)
    if len(values) != 1:
        fail(f"metadata field {name!r} is missing or repeated")
    return values[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=pathlib.Path, required=True)
    args = parser.parse_args()
    with zipfile.ZipFile(args.archive) as package:
        members = package.infolist()
        all_names = [item.filename for item in members]
        names = [item.filename for item in members if not item.is_dir()]
        if len(all_names) != len(set(all_names)):
            fail("archive contains duplicate entries")
        if len(all_names) != len({name.casefold() for name in all_names}):
            fail("archive contains case-insensitive duplicate entries")
        unsafe = [
            name
            for name in all_names
            if pathlib.PurePosixPath(name).is_absolute()
            or pathlib.PureWindowsPath(name).drive
            or ".." in pathlib.PurePosixPath(name).parts
            or "\\" in name
        ]
        if unsafe:
            fail(f"archive contains unsafe paths: {unsafe}")
        unsupported = [
            item.filename
            for item in members
            if not item.is_dir()
            and stat.S_IFMT(item.external_attr >> 16) not in {0, stat.S_IFREG}
        ]
        if unsupported:
            fail(f"archive contains unsupported entries: {unsupported}")
        missing = sorted(REQUIRED - set(names))
        if missing:
            fail(f"required publication files are missing: {missing}")
        forbidden = [
            name
            for name in names
            if any(
                part in {"_build", ".git", ".mooncakes", "__pycache__", ".vscode"}
                for part in pathlib.PurePosixPath(name).parts
            )
            or name == ".env"
            or pathlib.PurePosixPath(name).name == "credentials.json"
            or name.endswith((".key", ".pem", ".profraw", ".pyc", ".pyo"))
        ]
        if forbidden:
            fail(f"build/cache/credential files were packaged: {forbidden}")
        manifest = package.read("moon.mod").decode()
        if field(manifest, "name") != "moonbit-community/MoonJust":
            fail("module name differs")
        if not re.fullmatch(r"0\.7\.0-alpha\.[1-9][0-9]*", field(manifest, "version")):
            fail("Phase 11 version is not a numbered 0.7.0 alpha prerelease")
        if field(manifest, "readme") != "README.mbt.md":
            fail("readme metadata differs")
        if field(manifest, "repository") != "https://github.com/moonbit-community/MoonJust":
            fail("repository metadata differs")
        if field(manifest, "license") != "Apache-2.0":
            fail("license metadata differs")
        for keyword in ("command-runner", "just", "task-runner", "wasm"):
            if f'"{keyword}"' not in manifest:
                fail(f"keyword {keyword!r} is missing")
    print(f"Phase 11 source package verified: {len(names)} safe publication entries")


if __name__ == "__main__":
    main()
