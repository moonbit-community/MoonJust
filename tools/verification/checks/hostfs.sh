#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
binary="$repo_root/_build/wasm/debug/build/tools/probes/hostfs_probe/hostfs_probe.wasm"
allow_policy="$repo_root/policies/filesystem.toml"
deny_policy="$repo_root/policies/inspect.toml"
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-hostfs.XXXXXX")

cleanup() {
  rm -rf "$work"
  rm -f "$repo_root/_build/moonjust-wasm-policy-transaction"
  find "$repo_root/_build" -maxdepth 1 -name '.moonjust.tmp.*' -delete
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "HostFs error: $1" >&2
  exit 1
}

grep -Eq '^write = \["\.\./"\]$' "$allow_policy" || \
  fail "filesystem policy does not scope writes to the repository"
grep -Eq '^write = \[\]$' "$deny_policy" || \
  fail "inspect policy unexpectedly grants writes"

moon build --target wasm tools/probes/hostfs_probe
[ -f "$binary" ] || fail "wasm HostFs probe is missing"

moonrun --policy "$allow_policy" "$binary" allow \
  >"$work/allow.stdout" 2>"$work/allow.stderr"
[ "$(cat "$work/allow.stdout")" = \
  'allow: atomic replace, CRLF, no-overwrite, cleanup' ] || \
  fail "allowed transaction result changed"
[ ! -s "$work/allow.stderr" ] || fail "allowed transaction emitted stderr"

moonrun --policy "$deny_policy" "$binary" deny \
  >"$work/deny.stdout" 2>"$work/deny.stderr"
[ "$(cat "$work/deny.stdout")" = \
  'deny: typed write denial, cleanup' ] || \
  fail "denied transaction result changed"
deny_lines=$(wc -l <"$work/deny.stderr" | tr -d ' ')
[ "$deny_lines" -eq 2 ] || fail "denied transaction emitted unexpected diagnostics"
[ "$(sort -u "$work/deny.stderr" | wc -l | tr -d ' ')" -eq 1 ] || \
  fail "denied create and cleanup did not target the same temporary file"
grep -Eq '^Sandbox policy blocked file write: "_build/\.moonjust\.tmp\.[0-9a-f]{24}"$' \
  "$work/deny.stderr" || fail "denied transaction diagnostic changed"

echo "HostFs policies verified: allowed atomic commit and typed denial"
