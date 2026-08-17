#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
cd "$repo_root"
report_only=
if [ "${1:-}" = "--report-only" ]; then
  report_only=--report-only
elif [ "$#" -ne 0 ]; then
  echo "usage: $0 [--report-only]" >&2
  exit 2
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
  $report_only
