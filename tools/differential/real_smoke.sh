#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
oracle_root="$repo_root/_build/upstream/just-1.57.0"
oracle="${MOONJUST_ORACLE_CANDIDATE:-$oracle_root/target/release/just}"
candidate="${MOONJUST_NATIVE_CANDIDATE:-$repo_root/_build/native/debug/build/cmd/just/just.exe}"
candidate_wasm="${MOONJUST_WASM_CANDIDATE:-$repo_root/_build/wasm/debug/build/cmd/just/just.wasm}"
metadata="$repo_root/_build/differential/oracle-metadata.txt"

python3 - "$repo_root/tests/differential/cases.toml" <<'PY'
import sys
import tomllib
from pathlib import Path

manifest = tomllib.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
cases = manifest.get("case", [])
if manifest.get("schema_version") != 3:
    raise SystemExit("differential manifest must use schema version 3")
if len(cases) != 182:
    raise SystemExit(f"differential manifest expected 182 cases, found {len(cases)}")
seen = set()
for case in cases:
    case_id = case.get("id")
    if case_id in seen:
        raise SystemExit(f"duplicate differential case id: {case_id}")
    seen.add(case_id)
    status = case.get("status")
    if status not in {"match", "expected-difference"}:
        raise SystemExit(f"case {case_id} is not explicitly classified")
    if not isinstance(case.get("upstream_tests", []), list):
        raise SystemExit(f"case {case_id} has invalid upstream_tests")
    if status == "expected-difference" and case.get("allowed_difference", "none") == "none":
        raise SystemExit(f"case {case_id} has an unbounded expected difference")
    if case.get("owner_area") not in {
        "query-cli",
        "execution-context",
        "executor",
        "runtime-cache",
        "platform-compatibility",
    }:
        raise SystemExit(f"case {case_id} has an invalid owner area")
    case_dir = Path(sys.argv[1]).parent / "cases" / case["directory"]
    if not (case_dir / "expectation").exists():
        raise SystemExit(f"case {case_id} is missing expectation")
    expected = "difference" if status == "expected-difference" else "match"
    if (case_dir / "expectation").read_text(encoding="utf-8").strip() != expected:
        raise SystemExit(f"case {case_id} expectation does not match manifest status")
    if not (case_dir / "compat-id").exists():
        raise SystemExit(f"case {case_id} is missing compat-id")
    if (case_dir / "compat-id").read_text(encoding="utf-8").strip() != case_id:
        raise SystemExit(f"case {case_id} compat-id does not match manifest")
PY

mkdir -p "$(dirname -- "$metadata")"
if [ -z "${MOONJUST_ORACLE_CANDIDATE:-}" ]; then
  "$repo_root/tools/upstream/build_oracle.sh" | tee "$metadata"
else
  printf 'oracle=%s\n' "$oracle" >"$metadata"
fi
if [ -z "${MOONJUST_NATIVE_CANDIDATE:-}" ]; then moon build --target native cmd/just; fi
if [ -z "${MOONJUST_WASM_CANDIDATE:-}" ]; then moon build --target wasm cmd/just; fi
[ -x "$candidate" ] || {
  echo "real differential error: candidate binary is missing: $candidate" >&2
  exit 1
}
[ -f "$candidate_wasm" ] || {
  echo "real differential error: wasm candidate is missing: $candidate_wasm" >&2
  exit 1
}

[ -x "$oracle" ] || {
  echo "real differential error: oracle binary is missing: $oracle" >&2
  exit 1
}

"$script_dir/run.sh" \
  --upstream "$oracle" \
  --candidate-native "$candidate" \
  --candidate-wasm "$candidate_wasm" \
  --wasm-policy "$repo_root/policies/execute.toml" \
  --artifacts "$repo_root/_build/differential/real"
