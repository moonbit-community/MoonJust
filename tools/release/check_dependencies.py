#!/usr/bin/env python3
import pathlib
import re
import subprocess
import json


ROOT = pathlib.Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    raise SystemExit(f"Phase 11 dependency audit error: {message}")


text = (ROOT / "moon.mod").read_text()
block = re.search(r"^import \{\n(.*?)^\}", text, re.M | re.S)
if block is None:
    fail("moon.mod import block is missing")
declared = re.findall(r'^\s*"([^"@]+)@([^"@]+)",\s*$', block.group(1), re.M)
if len(declared) != len([line for line in block.group(1).splitlines() if line.strip()]):
    fail("every production dependency must be an exact registry name@version string")
if len(declared) != len(set(declared)):
    fail("production dependency is repeated")

tree = subprocess.run(
    ["moon", "tree"], cwd=ROOT, check=True, text=True, capture_output=True
).stdout.splitlines()[1:]
resolved = set()
for line in tree:
    match = re.match(r"^[^A-Za-z0-9]*([^ ]+) -> ([^@ ]+)@([^ ]+)$", line)
    if not match:
        continue
    alias, name, version = match.groups()
    if alias != name:
        fail(f"dependency alias {alias!r} differs from module {name!r}")
    resolved.add((name, version))
if resolved != set(declared):
    fail(f"declared/resolved dependencies differ: {declared!r} vs {sorted(resolved)!r}")

for name, version in declared:
    module = ROOT / ".mooncakes" / name / "moon.mod"
    legacy = module.with_name("moon.mod.json")
    if module.is_file():
        metadata = module.read_text()
        license_match = re.search(r'^license = "([^"]+)"$', metadata, re.M)
        version_match = re.search(r'^version = "([^"]+)"$', metadata, re.M)
        license_value = license_match.group(1) if license_match else None
        version_value = version_match.group(1) if version_match else None
    elif legacy.is_file():
        metadata = json.loads(legacy.read_text())
        license_value = metadata.get("license")
        version_value = metadata.get("version")
    else:
        fail(f"resolved source is missing for {name}@{version}")
    if license_value is None:
        fail(f"dependency {name}@{version} has no SPDX license metadata")
    if license_value not in {"Apache-2.0", "MIT", "BSD-3-Clause"}:
        fail(f"dependency {name}@{version} uses unreviewed license {license_value}")
    if version_value != version:
        fail(f"dependency source version differs for {name}@{version}")

print(f"Phase 11 dependency audit verified: {len(declared)} exact registry dependencies and licenses")
