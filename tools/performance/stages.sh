#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
target=${1:-native}
case "$target" in
  native|wasm) ;;
  *) echo "usage: $0 [native|wasm]" >&2; exit 2 ;;
esac

cd "$repo_root"
moon bench --frozen --release --target "$target" --no-parallelize \
  internal/lexer \
  internal/parser \
  internal/semantic \
  internal/formatter \
  internal/evaluator \
  internal/executor
