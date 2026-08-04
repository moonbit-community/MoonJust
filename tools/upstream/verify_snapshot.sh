#!/bin/sh
set -eu

expected_tests=2417
expected_test_sha=34773c9c59398fe3ac490aa7239b3c33a7b615159ff59b1e85ddef5e802381d9
expected_options=50
expected_commands=19
expected_builtins=83
expected_phase_one_contracts=5

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
test_list="$repo_root/tests/upstream/just-1.57.0/test-list.txt"

fail() {
  echo "compatibility snapshot error: $1" >&2
  exit 1
}

actual_tests=$(wc -l <"$test_list" | tr -d ' ')
[ "$actual_tests" = "$expected_tests" ] || \
  fail "expected $expected_tests tests, found $actual_tests"

if command -v sha256sum >/dev/null 2>&1; then
  actual_test_sha=$(sha256sum "$test_list" | awk '{ print $1 }')
else
  actual_test_sha=$(shasum -a 256 "$test_list" | awk '{ print $1 }')
fi
[ "$actual_test_sha" = "$expected_test_sha" ] || \
  fail "test-list SHA-256 is $actual_test_sha"

actual_options=$(grep -c '^\[\[option\]\]$' "$repo_root/compat/cli-options.toml")
[ "$actual_options" = "$expected_options" ] || \
  fail "expected $expected_options CLI options, found $actual_options"

actual_commands=$(grep -c '^\[\[command\]\]$' "$repo_root/compat/cli-options.toml")
[ "$actual_commands" = "$expected_commands" ] || \
  fail "expected $expected_commands CLI commands, found $actual_commands"

actual_builtins=$(grep -c '^  "[a-z0-9_]*",$' "$repo_root/compat/builtins.toml")
[ "$actual_builtins" = "$expected_builtins" ] || \
  fail "expected $expected_builtins builtins, found $actual_builtins"

phase_one_manifest="$repo_root/compat/phase-1.toml"
actual_phase_one_contracts=$(grep -c '^\[\[contract\]\]$' "$phase_one_manifest")
[ "$actual_phase_one_contracts" = "$expected_phase_one_contracts" ] || \
  fail "expected $expected_phase_one_contracts Phase 1 contracts, found $actual_phase_one_contracts"

implemented_phase_one_contracts=$(grep -c '^status = "implemented"$' "$phase_one_manifest")
[ "$implemented_phase_one_contracts" = "$expected_phase_one_contracts" ] || \
  fail "expected all Phase 1 contracts to be implemented"

native_phase_one_contracts=$(grep -c '^native = "pass"$' "$phase_one_manifest")
[ "$native_phase_one_contracts" = "$expected_phase_one_contracts" ] || \
  fail "expected all Phase 1 contracts to pass Native"

wasm_phase_one_contracts=$(grep -c '^wasm1 = "pass"$' "$phase_one_manifest")
[ "$wasm_phase_one_contracts" = "$expected_phase_one_contracts" ] || \
  fail "expected all Phase 1 contracts to pass wasm1"

echo "compatibility snapshot verified"
