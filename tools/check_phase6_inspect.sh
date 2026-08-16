#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
binary="$repo_root/_build/wasm/debug/build/cmd/just/just.wasm"
policy="$repo_root/policies/inspect.toml"
fixture="$repo_root/tests/fixtures/phase-6/justfile"
unformatted="$repo_root/tests/fixtures/phase-6/unformatted.justfile"
effect="$repo_root/tests/fixtures/phase-6/effect.justfile"
marker="$repo_root/_build/phase-6-process-marker"
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-phase6.XXXXXX")

cleanup() {
  rm -rf "$work"
  rm -f "$marker"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "Phase 6 inspect error: $1" >&2
  exit 1
}

grep -Eq '^write = \[\]$' "$policy" || fail "inspect policy grants filesystem writes"
grep -Eq '^spawn = false$' "$policy" || fail "inspect policy grants process spawn"

moon build --target wasm cmd/just
[ -f "$binary" ] || fail "wasm CLI artifact is missing"

moonrun --policy "$policy" "$binary" \
  --list --justfile "$fixture" >"$work/list.stdout" 2>"$work/list.stderr"
expected='Available recipes:
    hello # greeting'
[ "$(cat "$work/list.stdout")" = "$expected" ] || fail "list output changed"
[ ! -s "$work/list.stderr" ] || fail "list emitted stderr"

before=$(cksum "$unformatted")
if moonrun --policy "$policy" "$binary" \
  --fmt --justfile "$unformatted" >"$work/fmt.stdout" 2>"$work/fmt.stderr"; then
  fail "read-only policy allowed format write"
fi
[ "$before" = "$(cksum "$unformatted")" ] || fail "format changed the fixture"
grep -Eq 'error: failed to write justfile .*: Permission denied \(os error 13\)' \
  "$work/fmt.stderr" || fail "format denial lost its stable user diagnostic"

rm -f "$marker"
if moonrun --policy "$policy" "$binary" \
  --justfile "$effect" --evaluate danger \
  >"$work/effect.stdout" 2>"$work/effect.stderr"; then
  fail "effectful evaluate unexpectedly succeeded"
fi
[ ! -e "$marker" ] || fail "inspect evaluation launched a process"
grep -q 'error\[MJ-EVAL-0004\]' "$work/effect.stderr" || \
  fail "effectful evaluate lost its stable error code"
grep -q 'PermissionDenied(Process' "$work/effect.stderr" || \
  fail "effectful evaluate did not report process denial"

echo "Phase 6 Wasm inspect policy verified: read-only fs, no process"
