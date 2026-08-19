#!/usr/bin/env bash
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
cd "$repo_root"
out="$repo_root/_build/coverage"
report_only=
if [ "${1:-}" = "--report-only" ]; then
  report_only=--report-only
elif [ "$#" -ne 0 ]; then
  echo "usage: $0 [--report-only]" >&2
  exit 2
fi

moon clean --quiet
mkdir -p "$out"
python3 "$repo_root/tools/quality/collect_coverage.py" \
  --repo "$repo_root" --target native --output "$out"
python3 "$repo_root/tools/quality/collect_coverage.py" \
  --repo "$repo_root" --target wasm --output "$out"
python3 "$repo_root/tools/quality/merge_coverage.py" \
  "$out/native.raw.xml" "$out/wasm.raw.xml" \
  --repo "$repo_root" \
  --cobertura "$out/cobertura.xml" \
  --summary "$out/summary.json" \
  --baseline "$repo_root/compat/coverage-baseline.json" \
  $report_only
