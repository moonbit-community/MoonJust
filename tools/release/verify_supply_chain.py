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
    raise SystemExit(f"Phase 11 supply-chain error: {message}")


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_digest(path: pathlib.Path) -> str:
    hasher = hashlib.sha256()
    files = []
    for item in path.rglob("*"):
        relative = item.relative_to(path)
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
        "https://github.com/moonbit-community/MoonJust/tools/release/build_artifacts.sh",
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
    if component.get("name") != module_name or component.get("version") != module_version:
        fail("SBOM module identity differs from moon.mod")
    application_ref = f"pkg:mooncakes/{module_name}@{module_version}"
    if component.get("bom-ref") != application_ref or component.get("purl") != application_ref:
        fail("SBOM application package URL differs")
    if component.get("licenses") != [{"license": {"id": module_field(args.repo, "license")}}]:
        fail("SBOM application license differs")
    hashes = {(item.get("alg"), item.get("content")) for item in component.get("hashes", [])}
    if ("SHA-256", expected_digest) not in hashes:
        fail("SBOM artifact digest differs")
    actual_dependencies = {
        (item.get("name"), item.get("version")) for item in sbom.get("components", [])
    }
    if actual_dependencies != expected_dependencies:
        fail("SBOM dependency set differs from moon.mod")
    actual_purls = {item.get("purl") for item in sbom.get("components", [])}
    expected_purls = {f"pkg:mooncakes/{name}@{version}" for name, version in expected_dependencies}
    if actual_purls != expected_purls:
        fail("SBOM package URLs differ from resolved dependencies")
    expected_component_details = {}
    for name, version in expected_dependencies:
        purl = f"pkg:mooncakes/{name}@{version}"
        source = args.repo / ".mooncakes" / name
        expected_component_details[purl] = {
            "hashes": [{"alg": "SHA-256", "content": source_digest(source)}],
            "licenses": [{"license": {"id": dependency_license(source)}}],
        }
    for item in sbom.get("components", []):
        purl = item.get("purl")
        if item.get("bom-ref") != purl or purl not in expected_component_details:
            fail("SBOM dependency reference differs")
        expected = expected_component_details[purl]
        if item.get("hashes") != expected["hashes"] or item.get("licenses") != expected["licenses"]:
            fail("SBOM dependency source digest or license differs")
    expected_graph = [
        {"ref": application_ref, "dependsOn": sorted(expected_purls)},
        *[{"ref": purl, "dependsOn": []} for purl in sorted(expected_purls)],
    ]
    actual_graph = [
        {"ref": item.get("ref"), "dependsOn": sorted(item.get("dependsOn", []))}
        for item in sbom.get("dependencies", [])
    ]
    if sorted(actual_graph, key=lambda item: str(item["ref"])) != sorted(
        expected_graph, key=lambda item: str(item["ref"])
    ):
        fail("SBOM dependency graph differs")

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
    tools = definition.get("internalParameters", {}).get("toolchain", {})
    if tools != toolchain():
        fail("provenance toolchain differs from the verifier toolchain")
    reproducibility = definition.get("internalParameters", {}).get(
        "reproducibility", {}
    )
    if reproducibility != {"SOURCE_DATE_EPOCH": "0", "ZERO_AR_DATE": "1"}:
        fail("provenance reproducibility parameters differ")
    if definition.get("internalParameters", {}).get("sourceDirty") is not expected_dirty:
        fail("provenance source state differs")
    resolved = definition.get("resolvedDependencies", [])
    expected_resolved = [
        {
            "uri": "git+https://github.com/moonbit-community/MoonJust",
            "digest": expected_commit,
        },
        *[
            {
                "uri": purl,
                "digest": expected_component_details[purl]["hashes"][0]["content"],
            }
            for purl in sorted(expected_purls)
        ],
    ]
    actual_resolved = sorted(
        (
            {
                "uri": item.get("uri"),
                "digest": item.get("digest", {}).get(
                    "sha256", item.get("digest", {}).get("gitCommit")
                ),
            }
            for item in resolved
        ),
        key=lambda item: str(item["uri"]),
    )
    if actual_resolved != expected_resolved:
        fail("provenance dependencies differ from moon.mod")
    builder = predicate.get("runDetails", {}).get("builder", {}).get("id")
    if builder != expected_builder:
        fail("provenance builder identity differs")
    print("Phase 11 supply chain verified: artifact, SBOM, dependencies, commit, target, toolchain")
    return 0


if __name__ == "__main__":
    sys.exit(main())
