#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
oracle_root="$repo_root/_build/upstream/just-1.57.0"
oracle="${MOONJUST_ORACLE_CANDIDATE:-$oracle_root/target/release/just}"
native="${MOONJUST_NATIVE_CANDIDATE:-$repo_root/_build/native/debug/build/cmd/just/just.exe}"
wasm="${MOONJUST_WASM_CANDIDATE:-$repo_root/_build/wasm/debug/build/cmd/just/just.wasm}"
policy="$repo_root/policies/inspect.toml"
fixture="$repo_root/tests/fixtures/query/query.justfile"
json_fixture="$repo_root/tests/fixtures/query/json-arg.justfile"
groups_fixture="$repo_root/tests/fixtures/query/groups.justfile"
json_settings_fixture="$repo_root/tests/fixtures/query/json-settings.justfile"
json_attributes_fixture="$repo_root/tests/fixtures/query/json-attributes.justfile"
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-inspect-oracle.XXXXXX")

cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "Query compatibility error: $1" >&2
  exit 1
}

compare() {
  name=$1
  shift
  upstream_status=0
  native_status=0
  wasm_status=0
  "$oracle" --justfile "$fixture" "$@" \
    >"$work/$name.upstream.stdout" 2>"$work/$name.upstream.stderr" || upstream_status=$?
  "$native" --justfile "$fixture" "$@" \
    >"$work/$name.native.stdout" 2>"$work/$name.native.stderr" || native_status=$?
  moonrun --policy "$policy" "$wasm" --justfile "$fixture" "$@" \
    >"$work/$name.wasm.stdout" 2>"$work/$name.wasm.stderr" || wasm_status=$?
  [ "$native_status" -eq "$upstream_status" ] || \
    fail "$name native exit status differs ($native_status != $upstream_status)"
  [ "$wasm_status" -eq "$upstream_status" ] || \
    fail "$name wasm exit status differs ($wasm_status != $upstream_status)"
  cmp -s "$work/$name.upstream.stdout" "$work/$name.native.stdout" || \
    fail "$name native stdout differs"
  cmp -s "$work/$name.upstream.stderr" "$work/$name.native.stderr" || \
    fail "$name native stderr differs"
  cmp -s "$work/$name.upstream.stdout" "$work/$name.wasm.stdout" || \
    fail "$name wasm stdout differs"
  cmp -s "$work/$name.upstream.stderr" "$work/$name.wasm.stderr" || \
    fail "$name wasm stderr differs"
}

if [ -z "${MOONJUST_ORACLE_CANDIDATE:-}" ]; then "$repo_root/tools/upstream/build_oracle.sh" >/dev/null; fi
if [ -z "${MOONJUST_NATIVE_CANDIDATE:-}" ]; then moon build --target native cmd/just; fi
if [ -z "${MOONJUST_WASM_CANDIDATE:-}" ]; then moon build --target wasm cmd/just; fi
[ -x "$oracle" ] || fail "upstream oracle is missing"
[ -x "$native" ] || fail "native CLI is missing"
[ -f "$wasm" ] || fail "wasm CLI is missing"

compare list --list
compare list-left --list --alias-style left
compare list-separate --list --alias-style separate
compare summary --summary
compare groups --groups
compare variables --variables
compare evaluate --evaluate
compare evaluate-one --evaluate y
compare dump --dump
compare json --unstable --json
fixture="$json_fixture"
compare json-arg --unstable --dump --dump-format json
compare list-options --unstable --list
compare usage-options --unstable --usage foo
fixture="$json_settings_fixture"
compare json-settings --unstable --dump --dump-format json
fixture="$json_attributes_fixture"
compare json-attributes --unstable --dump --dump-format json
fixture="$groups_fixture"
compare list-groups --list
compare list-groups-unsorted --list --unsorted
compare list-selected-groups --list --group alpha --group beta
compare multiple-groups --groups
fixture="$repo_root/tests/fixtures/query/query.justfile"
compare show --show h
compare usage --usage h
compare show-suggestion --show hell
compare show-no-suggestion --show zzzzzzzz
fixture="$repo_root/tests/fixtures/query/empty.justfile"
compare summary-empty --summary

echo "Query compatibility verified: 24 Native/Wasm query cases match just 1.57.0"
