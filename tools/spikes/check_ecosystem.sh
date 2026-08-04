#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
spike="$repo_root/spikes/ecosystem"
expected='Total tests: 10, passed: 10, failed: 0.'

moon -C "$spike" fmt --check
moon -C "$spike" check --target native --warn-list +73
moon -C "$spike" check --target wasm --warn-list +73

run_contract() {
  target=$1
  output=$(moon -C "$spike" test --target "$target" 2>&1)
  printf '%s\n' "$output"
  if ! printf '%s\n' "$output" | grep -F "$expected" >/dev/null; then
    echo "ecosystem spike selected an unexpected test count for $target" >&2
    exit 1
  fi
}

run_contract native
run_contract wasm
