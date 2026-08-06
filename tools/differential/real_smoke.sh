#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
oracle_root="$repo_root/_build/upstream/just-1.57.0"
candidate="$repo_root/_build/native/debug/build/cmd/just/just.exe"
metadata="$repo_root/_build/differential/oracle-metadata.txt"

python3 - "$repo_root/tests/differential/cases.toml" <<'PY'
import sys
import tomllib
from pathlib import Path

manifest = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
cases = manifest.get("case", [])
if len(cases) != 10:
    raise SystemExit(f"differential manifest expected 10 cases, found {len(cases)}")
seen = set()
for case in cases:
    case_id = case.get("id")
    if case_id in seen:
        raise SystemExit(f"duplicate differential case id: {case_id}")
    seen.add(case_id)
    if case.get("status") != "expected-difference":
        raise SystemExit(f"case {case_id} is not explicitly classified")
    if not isinstance(case.get("owner_phase"), int) or case["owner_phase"] < 6:
        raise SystemExit(f"case {case_id} must be owned by a later phase")
    case_dir = Path(sys.argv[1]).parent / "cases" / case["directory"]
    if not (case_dir / "expectation").exists() or not (case_dir / "compat-id").exists():
        raise SystemExit(f"case {case_id} is missing expectation or compat-id")
    if (case_dir / "compat-id").read_text(encoding="utf-8").strip() != case_id:
        raise SystemExit(f"case {case_id} compat-id does not match manifest")
PY

mkdir -p "$(dirname -- "$metadata")"
"$repo_root/tools/upstream/build_oracle.sh" | tee "$metadata"
moon build --target native cmd/just
[ -x "$candidate" ] || {
  echo "real differential error: candidate binary is missing: $candidate" >&2
  exit 1
}

oracle="$oracle_root/target/release/just"
[ -x "$oracle" ] || {
  echo "real differential error: oracle binary is missing: $oracle" >&2
  exit 1
}

"$script_dir/run.sh" \
  --upstream "$oracle" \
  --candidate "$candidate" \
  --artifacts "$repo_root/_build/differential/real"
