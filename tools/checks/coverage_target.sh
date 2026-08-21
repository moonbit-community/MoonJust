#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
cd "$repo_root"

target=${1:-}
if [ "$#" -ne 1 ] || [ "$target" != native ] && [ "$target" != wasm ]; then
  echo "usage: $0 native|wasm" >&2
  exit 2
fi

out="$repo_root/_build/coverage"
mkdir -p "$out"
python3 "$repo_root/tools/quality/collect_coverage.py" \
  --repo "$repo_root" --target "$target" --output "$out"
