#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
oracle="${MOONJUST_ORACLE_CANDIDATE:-$repo_root/_build/upstream/just-1.57.0/target/release/just}"
fixture="$repo_root/tests/fixtures/execution/line.justfile"
expected="$repo_root/tests/fixtures/execution/line.dry-run.stderr"
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-executor.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

fail() {
  echo "Executor gate failed: $1" >&2
  exit 1
}

if [ -z "${MOONJUST_ORACLE_CANDIDATE:-}" ]; then "$repo_root/tools/upstream/build_oracle.sh" >/dev/null; fi
[ -x "$oracle" ] || fail "upstream oracle is missing"

"$oracle" --dry-run --justfile "$fixture" build \
  >"$work/upstream.stdout" 2>"$work/upstream.stderr"
[ ! -s "$work/upstream.stdout" ] || fail "upstream dry-run stdout is not empty"
cmp -s "$expected" "$work/upstream.stderr" || {
  diff -u "$expected" "$work/upstream.stderr" || true
  fail "ordinary-line oracle changed"
}

moon test --target native internal/executor
moon test --target wasm internal/executor

cli_native="${MOONJUST_NATIVE_CANDIDATE:-$repo_root/_build/native/debug/build/cmd/just/just.exe}"
cli_wasm="${MOONJUST_WASM_CANDIDATE:-$repo_root/_build/wasm/debug/build/cmd/just/just.wasm}"
if [ -z "${MOONJUST_NATIVE_CANDIDATE:-}" ]; then moon build cmd/just --target native >/dev/null; fi
if [ -z "${MOONJUST_WASM_CANDIDATE:-}" ]; then moon build cmd/just --target wasm >/dev/null; fi
"$cli_native" \
  --justfile "$repo_root/tests/fixtures/execution/line.justfile" build \
  >"$work/native.stdout" 2>"$work/native.stderr"
grep -q '^hello world$' "$work/native.stdout" || fail "native CLI corpus did not execute"
moonrun --policy "$repo_root/policies/execute.toml" "$cli_wasm" \
  --justfile "$repo_root/tests/fixtures/execution/line.justfile" build \
  >"$work/wasm.stdout" 2>"$work/wasm.stderr"
cmp -s "$work/native.stdout" "$work/wasm.stdout" || fail "native/wasm stdout differs"

echo "Executor gate passed (oracle, native/wasm CLI corpus, and 15+15 executor cases)"
