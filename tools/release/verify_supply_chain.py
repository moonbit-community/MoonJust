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


def fail(message: str) -> None:
    raise SystemExit(f"Release supply-chain error: {message}")


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_digest(path: pathlib.Path) -> str:
    hasher = hashlib.sha256()
    files = []
    for duplicate in (item for item in path.rglob("*") if item.name.endswith(" 2")):
        if not duplicate.is_dir() or any(duplicate.iterdir()):
            fail(f"dependency duplicate directory is not empty: {duplicate}")
    for item in path.rglob("*"):
        relative = item.relative_to(path)
        if item.is_symlink():
            fail(f"dependency source tree contains a symlink: {path / relative}")
        if not item.is_file():
            continue
        if any(part in {".git", "_build"} or part.endswith(" 2") for part in relative.parts):
            continue
        if item.name.endswith(".profraw"):
            continue
        files.append((relative.as_posix(), item))
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
    fail(f"dependency license metadata is missing: {path}")


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


def dependencies(repo: pathlib.Path) -> set[tuple[str, str]]:
    output = subprocess.run(
        ["moon", "tree"], cwd=repo, check=True, text=True, capture_output=True
    ).stdout.splitlines()[1:]
    pattern = re.compile(r"^[^A-Za-z0-9]*([^ ]+) -> ([^@ ]+)@([^ ]+)$")
    result = set()
    for line in output:
        match = pattern.match(line)
        if not match:
            continue
        alias, name, version = match.groups()
        if alias != name:
            fail(f"dependency alias {alias!r} differs from module {name!r}")
        result.add((name, version))
    if not result:
        fail("moon tree returned no resolved dependencies")
    return result


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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=pathlib.Path, required=True)
    parser.add_argument("--artifact", type=pathlib.Path, required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--sbom", type=pathlib.Path, required=True)
    parser.add_argument("--provenance", type=pathlib.Path, required=True)
    args = parser.parse_args()

    module_name = module_field(args.repo, "name")
    module_version = module_field(args.repo, "version")
    expected_dependencies = dependencies(args.repo)
    expected_digest = digest(args.artifact)
    expected_commit = subprocess.run(
        ["git", "-C", str(args.repo), "rev-parse", "HEAD"],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    expected_build_uuid = uuid.uuid5(
        uuid.NAMESPACE_URL,
        f"https://github.com/moonbit-community/MoonJust/{expected_commit}/{args.target}/{expected_digest}",
    )
    expected_builder = os.environ.get(
        "MOONJUST_BUILDER_ID",
        "https://github.com/moonbit-community/MoonJust/tools/release/build_artifacts.py",
    )
    expected_dirty = bool(
        subprocess.run(
            [
                "git",
                "-C",
                str(args.repo),
                "status",
                "--porcelain",
                "--untracked-files=all",
            ],
            check=True,
            text=True,
            capture_output=True,
        ).stdout.strip()
    )

    sbom = json.loads(args.sbom.read_text())
    if sbom.get("$schema") != "http://cyclonedx.org/schema/bom-1.5.schema.json":
        fail("SBOM schema URI differs")
    if sbom.get("bomFormat") != "CycloneDX" or sbom.get("specVersion") != "1.5":
        fail("SBOM is not CycloneDX 1.5")
    if sbom.get("serialNumber") != f"urn:uuid:{expected_build_uuid}":
        fail("SBOM serial number differs")
    component = sbom.get("metadata", {}).get("component", {})
    application_ref = f"pkg:mooncakes/{module_name}@{module_version}"
    expected_application_component = {
        "type": "application",
        "bom-ref": application_ref,
        "name": module_name,
        "version": module_version,
        "purl": application_ref,
        "hashes": [{"alg": "SHA-256", "content": expected_digest}],
        "licenses": [{"license": {"id": module_field(args.repo, "license")}}],
    }
    if component != expected_application_component:
        fail("SBOM application component differs")
    if component.get("name") != module_name or component.get("version") != module_version:
        fail("SBOM module identity differs from moon.mod")
    if component.get("bom-ref") != application_ref or component.get("purl") != application_ref:
        fail("SBOM application package URL differs")
    if component.get("licenses") != [{"license": {"id": module_field(args.repo, "license")}}]:
        fail("SBOM application license differs")
    if component.get("hashes") != [{"alg": "SHA-256", "content": expected_digest}]:
        fail("SBOM artifact digest differs")
    expected_purls = {f"pkg:mooncakes/{name}@{version}" for name, version in expected_dependencies}
    expected_component_details = {}
    for name, version in expected_dependencies:
        purl = f"pkg:mooncakes/{name}@{version}"
        source = args.repo / ".mooncakes" / name
        expected_component_details[purl] = {
            "hashes": [{"alg": "SHA-256", "content": source_digest(source)}],
            "licenses": [{"license": {"id": dependency_license(source)}}],
        }
    expected_components = [
        {
            "type": "library",
            "bom-ref": purl,
            "name": name,
            "version": version,
            "purl": purl,
            **expected_component_details[purl],
        }
        for name, version in sorted(expected_dependencies)
        for purl in [f"pkg:mooncakes/{name}@{version}"]
    ]
    if sorted(sbom.get("components", []), key=lambda item: str(item.get("purl"))) != expected_components:
        fail("SBOM dependency components differ from resolved sources")
    expected_graph = [
        {"ref": application_ref, "dependsOn": sorted(expected_purls)},
        *[{"ref": purl, "dependsOn": []} for purl in sorted(expected_purls)],
    ]
    actual_graph = [
        {**item, "dependsOn": sorted(item.get("dependsOn", []))}
        for item in sbom.get("dependencies", [])
    ]
    if sorted(actual_graph, key=lambda item: str(item["ref"])) != sorted(
        expected_graph, key=lambda item: str(item["ref"])
    ):
        fail("SBOM dependency graph differs")
    expected_sbom = {
        "$schema": "http://cyclonedx.org/schema/bom-1.5.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": f"urn:uuid:{expected_build_uuid}",
        "version": 1,
        "metadata": {"component": expected_application_component},
        "components": expected_components,
        "dependencies": expected_graph,
    }
    normalized_sbom = {
        **sbom,
        "components": sorted(
            sbom.get("components", []), key=lambda item: str(item.get("purl"))
        ),
        "dependencies": sorted(
            actual_graph, key=lambda item: str(item.get("ref"))
        ),
    }
    expected_sbom["dependencies"] = sorted(
        expected_graph, key=lambda item: str(item.get("ref"))
    )
    if normalized_sbom != expected_sbom:
        fail("SBOM contains unexpected or missing fields")

    provenance = json.loads(args.provenance.read_text())
    if provenance.get("_type") != "https://in-toto.io/Statement/v1":
        fail("provenance statement type differs")
    if provenance.get("predicateType") != "https://slsa.dev/provenance/v1":
        fail("provenance predicate type differs")
    subjects = provenance.get("subject", [])
    expected_subject = {"name": args.artifact.name, "digest": {"sha256": expected_digest}}
    if subjects != [expected_subject]:
        fail("provenance subject or digest differs")
    predicate = provenance.get("predicate", {})
    definition = predicate.get("buildDefinition", {})
    if definition.get("buildType") != "https://github.com/moonbit-community/MoonJust/release-candidate/v1":
        fail("provenance build type differs")
    parameters = definition.get("externalParameters", {})
    if parameters != {"target": args.target, "version": module_version}:
        fail("provenance target or version differs")
    invocation = predicate.get("runDetails", {}).get("metadata", {}).get("invocationId")
    if invocation != f"urn:uuid:{expected_build_uuid}":
        fail("provenance invocation identity differs")
    expected_toolchain = toolchain()
    tools = definition.get("internalParameters", {}).get("toolchain", {})
    if tools != expected_toolchain:
        fail("provenance toolchain differs from the verifier toolchain")
    reproducibility = definition.get("internalParameters", {}).get(
        "reproducibility", {}
    )
    if reproducibility != {"SOURCE_DATE_EPOCH": "0", "ZERO_AR_DATE": "1"}:
        fail("provenance reproducibility parameters differ")
    if definition.get("internalParameters", {}).get("sourceDirty") is not expected_dirty:
        fail("provenance source state differs")
    resolved = definition.get("resolvedDependencies", [])
    expected_resolved_descriptors = [
        {
            "uri": "git+https://github.com/moonbit-community/MoonJust",
            "digest": {"gitCommit": expected_commit},
        },
        *[
            {
                "uri": purl,
                "digest": {
                    "sha256": expected_component_details[purl]["hashes"][0]["content"]
                },
            }
            for purl in sorted(expected_purls)
        ],
    ]
    if resolved != expected_resolved_descriptors:
        fail("provenance dependencies differ from moon.mod")
    builder = predicate.get("runDetails", {}).get("builder", {}).get("id")
    if builder != expected_builder:
        fail("provenance builder identity differs")
    expected_provenance = {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [expected_subject],
        "predicateType": "https://slsa.dev/provenance/v1",
        "predicate": {
            "buildDefinition": {
                "buildType": "https://github.com/moonbit-community/MoonJust/release-candidate/v1",
                "externalParameters": {"target": args.target, "version": module_version},
                "internalParameters": {
                    "toolchain": expected_toolchain,
                    "reproducibility": {
                        "SOURCE_DATE_EPOCH": "0",
                        "ZERO_AR_DATE": "1",
                    },
                    "sourceDirty": expected_dirty,
                },
                "resolvedDependencies": expected_resolved_descriptors,
            },
            "runDetails": {
                "builder": {"id": expected_builder},
                "metadata": {"invocationId": f"urn:uuid:{expected_build_uuid}"},
            },
        },
    }
    if provenance != expected_provenance:
        fail("provenance contains unexpected or missing fields")
    print("Release supply chain verified: artifact, SBOM, dependencies, commit, target, toolchain")
    return 0


if __name__ == "__main__":
    sys.exit(main())
