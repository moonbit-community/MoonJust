#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
oracle_root="$repo_root/_build/upstream/just-1.57.0"
oracle="${MOONJUST_ORACLE_CANDIDATE:-$oracle_root/target/release/just}"
fixture="$repo_root/tests/fixtures/invocation/invocation.justfile"
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-invocation.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

fail() {
  echo "Invocation differential failed: $1" >&2
  exit 1
}

if [ -z "${MOONJUST_ORACLE_CANDIDATE:-}" ]; then "$repo_root/tools/upstream/build_oracle.sh" >/dev/null; fi
moon build --quiet --target native tools/probes/invocation_probe
probe="$repo_root/_build/native/debug/build/tools/probes/invocation_probe/invocation_probe.exe"
native="${MOONJUST_NATIVE_CANDIDATE:-$repo_root/_build/native/debug/build/cmd/just/just.exe}"
wasm="${MOONJUST_WASM_CANDIDATE:-$repo_root/_build/wasm/debug/build/cmd/just/just.wasm}"
policy="$repo_root/policies/inspect.toml"
[ -x "$oracle" ] || fail "upstream oracle is missing"
[ -x "$probe" ] || fail "candidate probe is missing"
if [ -z "${MOONJUST_NATIVE_CANDIDATE:-}" ]; then moon build --quiet --target native cmd/just; fi
if [ -z "${MOONJUST_WASM_CANDIDATE:-}" ]; then moon build --quiet --target wasm cmd/just; fi
[ -x "$native" ] || fail "Native CLI is missing"
[ -f "$wasm" ] || fail "Wasm CLI is missing"

compare_success() {
  name=$1
  shift
  "$oracle" --unstable --dry-run --justfile "$fixture" "$@" \
    >"$work/$name.oracle.stdout" 2>"$work/$name.oracle.stderr"
  "$probe" "$@" <"$fixture" \
    >"$work/$name.candidate.stdout" 2>"$work/$name.candidate.stderr"
  cmp -s "$work/$name.oracle.stderr" "$work/$name.candidate.stdout" || {
    diff -u "$work/$name.oracle.stderr" "$work/$name.candidate.stdout" || true
    fail "$name rendered command differs"
  }
  [ ! -s "$work/$name.oracle.stdout" ] || fail "$name upstream stdout is not empty"
  [ ! -s "$work/$name.candidate.stderr" ] || fail "$name candidate stderr is not empty"
}

compare_usage() {
  name=$1
  shift
  "$oracle" --unstable --justfile "$fixture" --usage "$@" \
    >"$work/$name.oracle.stdout" 2>"$work/$name.oracle.stderr"
  "$native" --unstable --justfile "$fixture" --usage "$@" \
    >"$work/$name.native.stdout" 2>"$work/$name.native.stderr"
  moonrun --policy "$policy" "$wasm" \
    --unstable --justfile "$fixture" --usage "$@" \
    >"$work/$name.wasm.stdout" 2>"$work/$name.wasm.stderr"
  for target in native wasm; do
    cmp -s "$work/$name.oracle.stdout" "$work/$name.$target.stdout" || {
      diff -u "$work/$name.oracle.stdout" "$work/$name.$target.stdout" || true
      fail "$name $target usage stdout differs"
    }
    cmp -s "$work/$name.oracle.stderr" "$work/$name.$target.stderr" || \
      fail "$name $target usage stderr differs"
  done
}

compare_error() {
  name=$1
  shift
  oracle_status=0
  candidate_status=0
  "$oracle" --unstable --dry-run --justfile "$fixture" "$@" \
    >"$work/$name.oracle.stdout" 2>"$work/$name.oracle.stderr" || oracle_status=$?
  "$probe" "$@" <"$fixture" \
    >"$work/$name.candidate.stdout" 2>"$work/$name.candidate.stderr" || candidate_status=$?
  [ "$oracle_status" -eq "$candidate_status" ] || \
    fail "$name exit status differs ($oracle_status != $candidate_status)"
  cmp -s "$work/$name.oracle.stdout" "$work/$name.candidate.stdout" || \
    fail "$name stdout differs"
  cmp -s "$work/$name.oracle.stderr" "$work/$name.candidate.stderr" || {
    diff -u "$work/$name.oracle.stderr" "$work/$name.candidate.stderr" || true
    fail "$name stderr differs"
  }
}

compare_success long-short probe --first alpha -s tail one two
compare_success equals-terminator probe --first=beta -s -- --literal -x
compare_success pattern-list build --kind release
compare_success positional-explicit plain value override
compare_success value-expression computed hello --selected
compare_success multiple-value expanded --repeat --repeat
compare_error missing-option build
compare_error unknown-option build --unknown value
compare_error pattern-mismatch build --kind profile
compare_error positional-mismatch plain
compare_error duplicate-option build --kind debug --kind release
compare_usage usage-probe probe
compare_usage usage-build build
compare_usage usage-plain plain

echo "Invocation differential passed (11 argv and 3 Native/Wasm usage cases against just 1.57.0)"
