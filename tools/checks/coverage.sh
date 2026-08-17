#!/bin/sh
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

report_target() {
  target=$1
  moon coverage clean
  moon test --target "$target" --enable-coverage --no-parallelize
  set --
  for source in $(find "$repo_root/_build/$target/debug/test" \
    -name '*.trace.source' -print); do
    set -- "$@" "$source"
  done
  [ "$#" -gt 0 ] || {
    echo "coverage gate error: no $target trace sources were generated" >&2
    exit 1
  }
  trace_count=0
  for trace in $(find "$repo_root/_build" -maxdepth 1 \
    -name 'moonbit_coverage_*' -print); do
    set -- "$@" -t "$trace"
    trace_count=$((trace_count + 1))
  done
  [ "$trace_count" -gt 0 ] || {
    echo "coverage gate error: no $target coverage traces were generated" >&2
    exit 1
  }
  moon_cove_report "$@" -f cobertura -o "$out/$target.raw.xml" \
    --source-paths "$repo_root" --ignore-missing-files
}

moon clean --quiet
mkdir -p "$out"
report_target native
report_target wasm
python3 "$repo_root/tools/quality/merge_coverage.py" \
  "$out/native.raw.xml" "$out/wasm.raw.xml" \
  --repo "$repo_root" \
  --cobertura "$out/cobertura.xml" \
  --summary "$out/summary.json" \
  --baseline "$repo_root/compat/coverage-baseline.json" \
  $report_only
