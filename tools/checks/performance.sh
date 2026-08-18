#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
cd "$repo_root"
report_only=
authoritative=
if [ "${1:-}" = "--report-only" ]; then
  report_only=--report-only
elif [ "$#" -ne 0 ]; then
  echo "usage: $0 [--report-only]" >&2
  exit 2
fi
if [ "${MOONJUST_PERF_AUTHORITATIVE:-0}" = 1 ]; then
  authoritative=--authoritative
fi

set --
if [ -n "${MOONJUST_BASELINE_NATIVE:-}" ] || [ -n "${MOONJUST_BASELINE_WASM:-}" ]; then
  [ -n "${MOONJUST_BASELINE_NATIVE:-}" ] && [ -n "${MOONJUST_BASELINE_WASM:-}" ] || {
    echo "performance gate error: both merge-base artifacts are required" >&2
    exit 1
  }
  set -- \
    --baseline-native "$MOONJUST_BASELINE_NATIVE" \
    --baseline-wasm "$MOONJUST_BASELINE_WASM"
fi

"$repo_root/tools/upstream/build_oracle.sh" >/dev/null
moon build --release --strip --target native cmd/just
moon build --release --strip --target wasm cmd/just
python3 "$repo_root/tools/performance/benchmark.py" \
  --official "$repo_root/_build/upstream/just-1.57.0/target/release/just" \
  --native "$repo_root/_build/native/release/build/cmd/just/just.exe" \
  --wasm "$repo_root/_build/wasm/release/build/cmd/just/just.wasm" \
  --policy "$repo_root/policies/execute.toml" \
  --output "$repo_root/_build/performance/results.json" \
  --raw-output "$repo_root/_build/performance/samples.jsonl" \
  "$@" \
  $authoritative $report_only
