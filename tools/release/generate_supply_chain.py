#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import uuid


def digest(path: pathlib.Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def source_digest(path: pathlib.Path) -> str:
    hasher = hashlib.sha256()
    files = []
    for duplicate in (item for item in path.rglob("*") if item.name.endswith(" 2")):
        if not duplicate.is_dir() or any(duplicate.iterdir()):
            raise SystemExit(f"dependency duplicate directory is not empty: {duplicate}")
    for item in path.rglob("*"):
        relative = item.relative_to(path)
        if item.is_symlink():
            raise SystemExit(f"dependency source tree contains a symlink: {path / relative}")
        if not item.is_file():
            continue
        if any(part in {".git", "_build"} or part.endswith(" 2") for part in relative.parts):
            continue
        if item.name.endswith(".profraw"):
            continue
        files.append((relative.as_posix(), item))
    if not files:
        raise SystemExit(f"dependency source tree is empty: {path}")
    for name, item in sorted(files):
        data = item.read_bytes()
        hasher.update(len(name.encode()).to_bytes(8, "big"))
        hasher.update(name.encode())
        hasher.update(len(data).to_bytes(8, "big"))
        hasher.update(data)
    return hasher.hexdigest()


def dependency_license(path: pathlib.Path) -> str:
    current = path / "moon.mod"
    legacy = path / "moon.mod.json"
    if current.is_file():
        values = re.findall(r'^license = "([^"]+)"$', current.read_text(), re.M)
        if len(values) == 1:
            return values[0]
    elif legacy.is_file():
        value = json.loads(legacy.read_text()).get("license")
        if isinstance(value, str):
            return value
    raise SystemExit(f"dependency license metadata is missing: {path}")


def toolchain() -> dict[str, str]:
    output = subprocess.run(
        ["moon", "version", "--all"], check=True, text=True, capture_output=True
    ).stdout.splitlines()
    values: dict[str, str] = {}
    for line in output:
        if not line.strip():
            continue
        name, _, value = line.partition(" ")
        if name in {"moon", "moonc", "moonrun"}:
            values[name] = value.strip().rsplit(" ", 1)[0]
    moonx = subprocess.run(
        ["moonx", "--version"], check=True, text=True, capture_output=True
    ).stdout.strip()
    values["moonx"] = moonx.removeprefix("moonx ")
    return values


def module_field(repo: pathlib.Path, name: str) -> str:
    pattern = re.compile(rf'^\s*{re.escape(name)}\s*=\s*"([^"]+)"\s*$')
    values = [
        match.group(1)
        for line in (repo / "moon.mod").read_text().splitlines()
        if (match := pattern.match(line))
    ]
    if len(values) != 1:
        raise SystemExit(f"moon.mod field {name!r} is missing or repeated")
    return values[0]


def dependencies(repo: pathlib.Path) -> list[dict[str, str]]:
    output = subprocess.run(
        ["moon", "tree"], cwd=repo, check=True, text=True, capture_output=True
    ).stdout.splitlines()[1:]
    result = []
    pattern = re.compile(r"^[^A-Za-z0-9]*([^ ]+) -> ([^@ ]+)@([^ ]+)$")
    for line in output:
        match = pattern.match(line)
        if not match:
            continue
        alias, name, version = match.groups()
        if alias != name:
            raise SystemExit(f"dependency alias {alias!r} differs from module {name!r}")
        source = repo / ".mooncakes" / name
        if not source.is_dir():
            raise SystemExit(f"dependency source is missing: {name}@{version}")
        result.append(
            {
                "name": name,
                "version": version,
                "license": dependency_license(source),
                "sha256": source_digest(source),
            }
        )
    if not result:
        raise SystemExit("moon tree returned no resolved dependencies")
    return sorted(result, key=lambda item: (item["name"], item["version"]))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--artifact", type=pathlib.Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    args = parser.parse_args()

    repo = args.repo.resolve()
    artifact = args.artifact.resolve()
    out = args.out.resolve()
    module_name = module_field(repo, "name")
    module_version = module_field(repo, "version")
    commit = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "HEAD"],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    resolved_dependencies = dependencies(repo)
    artifact_digest = digest(artifact)
    build_uuid = uuid.uuid5(
        uuid.NAMESPACE_URL,
        f"https://github.com/moonbit-community/MoonJust/{commit}/{args.target}/{artifact_digest}",
    )
    builder_id = os.environ.get(
        "MOONJUST_BUILDER_ID",
        "https://github.com/moonbit-community/MoonJust/tools/release/build_artifacts.sh",
    )
    source_dirty = bool(
        subprocess.run(
            ["git", "-C", str(repo), "status", "--porcelain", "--untracked-files=all"],
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip()
    )
    out.mkdir(parents=True, exist_ok=True)

    application_ref = f"pkg:mooncakes/{module_name}@{module_version}"
    components = [
        {
            "type": "library",
            "bom-ref": f"pkg:mooncakes/{dependency['name']}@{dependency['version']}",
            "name": dependency["name"],
            "version": dependency["version"],
            "purl": f"pkg:mooncakes/{dependency['name']}@{dependency['version']}",
            "hashes": [{"alg": "SHA-256", "content": dependency["sha256"]}],
            "licenses": [{"license": {"id": dependency["license"]}}],
        }
        for dependency in resolved_dependencies
    ]
    sbom = {
        "$schema": "http://cyclonedx.org/schema/bom-1.5.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": f"urn:uuid:{build_uuid}",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "bom-ref": application_ref,
                "name": module_name,
                "version": module_version,
                "purl": application_ref,
                "hashes": [{"alg": "SHA-256", "content": artifact_digest}],
                "licenses": [{"license": {"id": module_field(repo, "license")}}],
            }
        },
        "components": components,
        "dependencies": [
            {
                "ref": application_ref,
                "dependsOn": [component["bom-ref"] for component in components],
            },
            *[{"ref": component["bom-ref"], "dependsOn": []} for component in components],
        ],
    }
    provenance = {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [
            {"name": artifact.name, "digest": {"sha256": artifact_digest}}
        ],
        "predicateType": "https://slsa.dev/provenance/v1",
        "predicate": {
            "buildDefinition": {
                "buildType": "https://github.com/moonbit-community/MoonJust/release-candidate/v1",
                "externalParameters": {
                    "target": args.target,
                    "version": module_version,
                },
                "internalParameters": {
                    "toolchain": toolchain(),
                    "reproducibility": {
                        "SOURCE_DATE_EPOCH": "0",
                        "ZERO_AR_DATE": "1",
                    },
                    "sourceDirty": source_dirty,
                },
                "resolvedDependencies": [
                    {
                        "uri": "git+https://github.com/moonbit-community/MoonJust",
                        "digest": {"gitCommit": commit},
                    },
                    *[
                        {
                            "uri": f"pkg:mooncakes/{dependency['name']}@{dependency['version']}",
                            "digest": {"sha256": dependency["sha256"]},
                        }
                        for dependency in resolved_dependencies
                    ],
                ],
            },
            "runDetails": {
                "builder": {"id": builder_id},
                "metadata": {"invocationId": f"urn:uuid:{build_uuid}"},
            },
        },
    }
    (out / "sbom.cdx.json").write_text(json.dumps(sbom, indent=2) + "\n")
    (out / "provenance.intoto.json").write_text(
        json.dumps(provenance, indent=2) + "\n"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
