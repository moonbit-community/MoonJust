#!/bin/sh
set -eu

expected_tests=2417
expected_commit=e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f
expected_test_sha=34773c9c59398fe3ac490aa7239b3c33a7b615159ff59b1e85ddef5e802381d9
expected_options=50
expected_commands=19
expected_builtins=83
expected_phase_one_contracts=5
expected_phase_two_contracts=5
expected_lexer_registrations=93
expected_phase_three_settings=29
expected_phase_three_attributes=29
expected_phase_three_positive=58
expected_phase_three_negative=9
expected_phase_three_fuzz=10000
expected_phase_four_tests=7
expected_phase_five_tests=10
expected_phase_four_settings=29
expected_phase_four_attributes=29
expected_phase_four_loader_cases=4
expected_phase_five_registry=83

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
test_list="$repo_root/tests/upstream/just-1.57.0/test-list.txt"

fail() {
  echo "compatibility snapshot error: $1" >&2
  exit 1
}

python3 "$script_dir/test_map.py"

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

actual_lexer_registrations=$(grep -c '^lexer::tests::' "$test_list")
[ "$actual_lexer_registrations" = "$expected_lexer_registrations" ] || \
  fail "expected $expected_lexer_registrations lexer tests, found $actual_lexer_registrations"

phase_two_manifest="$repo_root/compat/phase-2.toml"
actual_phase_two_contracts=$(grep -c '^\[\[contract\]\]$' "$phase_two_manifest")
[ "$actual_phase_two_contracts" = "$expected_phase_two_contracts" ] || \
  fail "expected $expected_phase_two_contracts Phase 2 contracts, found $actual_phase_two_contracts"

implemented_phase_two_contracts=$(grep -c '^status = "implemented"$' "$phase_two_manifest")
[ "$implemented_phase_two_contracts" = "$expected_phase_two_contracts" ] || \
  fail "expected all Phase 2 contracts to be implemented"

native_phase_two_contracts=$(grep -c '^native = "pass"$' "$phase_two_manifest")
[ "$native_phase_two_contracts" = "$expected_phase_two_contracts" ] || \
  fail "expected all Phase 2 contracts to pass Native"

wasm_phase_two_contracts=$(grep -c '^wasm1 = "pass"$' "$phase_two_manifest")
[ "$wasm_phase_two_contracts" = "$expected_phase_two_contracts" ] || \
  fail "expected all Phase 2 contracts to pass wasm1"

grep -q '^registrations = 93$' "$phase_two_manifest" || \
  fail "Phase 2 manifest does not freeze 93 lexer registrations"
grep -q '^random_inputs = 100000$' "$phase_two_manifest" || \
  fail "Phase 2 manifest does not require 100000 hardening inputs"
grep -q '^adapted_success_cases = 16$' "$phase_two_manifest" || \
  fail "Phase 2 manifest success oracle count changed"
grep -q '^adapted_error_cases = 5$' "$phase_two_manifest" || \
  fail "Phase 2 manifest error oracle count changed"

phase_three_manifest="$repo_root/compat/phase-3.toml"
grep -q '^status = "remediation"$' "$phase_three_manifest" || \
  fail "Phase 3 remediation status is missing"
grep -q '^plan_exit = "pending"$' "$phase_three_manifest" || \
  fail "Phase 3 plan exit is not pending during remediation"
grep -q "^registered_settings = $expected_phase_three_settings$" "$phase_three_manifest" || \
  fail "Phase 3 settings inventory changed"
grep -q "^registered_attributes = $expected_phase_three_attributes$" "$phase_three_manifest" || \
  fail "Phase 3 attributes inventory changed"
grep -q "^positive_inventory_cases = $expected_phase_three_positive$" "$phase_three_manifest" || \
  fail "Phase 3 positive grammar corpus changed"
grep -q "^negative_cases = $expected_phase_three_negative$" "$phase_three_manifest" || \
  fail "Phase 3 negative grammar corpus changed"
grep -q "^fuzz_inputs = $expected_phase_three_fuzz$" "$phase_three_manifest" || \
  fail "Phase 3 fuzz input count changed"

phase_three_corpus="$repo_root/tests/upstream/just-1.57.0/phase-3.toml"
grep -q "^upstream_commit = \"$expected_commit\"$" "$phase_three_corpus" 2>/dev/null || \
  fail "Phase 3 corpus upstream commit changed"
grep -q '^license = "CC0-1.0"$' "$phase_three_corpus" || \
  fail "Phase 3 corpus license changed"

phase_four_manifest="$repo_root/compat/phase-4.toml"
grep -q '^status = "remediation"$' "$phase_four_manifest" || \
  fail "Phase 4 remediation status is missing"
grep -q '^plan_exit = "pending"$' "$phase_four_manifest" || \
  fail "Phase 4 plan exit is not pending during remediation"
grep -q "^native_tests = $expected_phase_four_tests$" "$phase_four_manifest" || \
  fail "Phase 4 Native evidence count changed"
grep -q "^wasm_tests = $expected_phase_four_tests$" "$phase_four_manifest" || \
  fail "Phase 4 wasm evidence count changed"
grep -q "^settings = $expected_phase_four_settings$" "$phase_four_manifest" || \
  fail "Phase 4 settings evidence changed"
grep -q "^attributes = $expected_phase_four_attributes$" "$phase_four_manifest" || \
  fail "Phase 4 attributes evidence changed"
grep -q "^loader_cases = $expected_phase_four_loader_cases$" "$phase_four_manifest" || \
  fail "Phase 4 loader evidence changed"
grep -q '^status = "remediation"$' "$repo_root/compat/settings.toml" || \
  fail "settings compatibility registry is not in remediation"
grep -q '^status = "remediation"$' "$repo_root/compat/attributes.toml" || \
  fail "attributes compatibility registry is not in remediation"
phase_four_corpus="$repo_root/tests/upstream/just-1.57.0/phase-4.toml"
grep -q "^upstream_commit = \"$expected_commit\"$" "$phase_four_corpus" || \
  fail "Phase 4 corpus upstream commit changed"
grep -q '^license = "CC0-1.0"$' "$phase_four_corpus" || \
  fail "Phase 4 corpus license changed"

phase_five_manifest="$repo_root/compat/phase-5.toml"
grep -q '^status = "remediation"$' "$phase_five_manifest" || \
  fail "Phase 5 remediation status is missing"
grep -q '^plan_exit = "pending"$' "$phase_five_manifest" || \
  fail "Phase 5 plan exit is not pending during remediation"
grep -q "^native_tests = $expected_phase_five_tests$" "$phase_five_manifest" || \
  fail "Phase 5 Native evidence count changed"
grep -q "^wasm_tests = $expected_phase_five_tests$" "$phase_five_manifest" || \
  fail "Phase 5 wasm evidence count changed"
grep -q "^canonical_builtins = $expected_phase_five_registry$" "$phase_five_manifest" || \
  fail "Phase 5 builtin registry evidence changed"
grep -q '^status = "remediation"$' "$repo_root/compat/builtins.toml" || \
  fail "builtin compatibility registry is not in remediation"
phase_five_corpus="$repo_root/tests/upstream/just-1.57.0/phase-5.toml"
grep -q "^upstream_commit = \"$expected_commit\"$" "$phase_five_corpus" || \
  fail "Phase 5 corpus upstream commit changed"
grep -q '^license = "CC0-1.0"$' "$phase_five_corpus" || \
  fail "Phase 5 corpus license changed"

echo "compatibility snapshot verified"
