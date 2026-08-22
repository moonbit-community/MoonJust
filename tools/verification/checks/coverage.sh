#!/usr/bin/env bash
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
cd "$repo_root"
out="$repo_root/_build/coverage"
report_only=
if [ "${1:-}" = "--report-only" ]; then
  report_only=--report-only
elif [ "$#" -ne 0 ]; then
  echo "usage: $0 [--report-only]" >&2
  exit 2
fi

mkdir -p "$out"
coverage_base="${MOONJUST_COVERAGE_BASE:-}"
if [ -z "$coverage_base" ] && [ -f "$repo_root/compat/stage0-coverage-baseline.sha" ]; then
  coverage_base=$(tr -d '[:space:]' < "$repo_root/compat/stage0-coverage-baseline.sha")
fi
base_args=()
if [ -n "$coverage_base" ]; then
  base_args+=(--base "$coverage_base")
fi
"$repo_root/tools/verification/checks/coverage_target.sh" native
"$repo_root/tools/verification/checks/coverage_target.sh" wasm
python3 "$repo_root/tools/quality/merge_coverage.py" \
  "$out/native.raw.xml" "$out/wasm.raw.xml" \
  --repo "$repo_root" \
  --cobertura "$out/cobertura.xml" \
  --summary "$out/summary.json" \
  --baseline "$repo_root/compat/coverage-baseline.json" \
  "${base_args[@]}" \
  $report_only
