#!/bin/sh
set -eu

expected_tests=2417
expected_test_sha=34773c9c59398fe3ac490aa7239b3c33a7b615159ff59b1e85ddef5e802381d9
expected_options=50
expected_commands=19
expected_builtins=83

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

echo "compatibility snapshot verified"
