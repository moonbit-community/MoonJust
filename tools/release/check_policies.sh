#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/release_lib.sh"
repo_root=$(release_repo_root)
wasm="$repo_root/_build/wasm/release/build/cmd/just/just.wasm"
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-policy.XXXXXX")

cleanup() {
  case "$work" in
    "${TMPDIR:-/tmp}"/moonjust-policy.*) rm -rf -- "$work" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

moon build --release --strip --target wasm cmd/just >/dev/null
[ -f "$wasm" ] || release_fail "wasm policy artifact is missing"
mkdir -p "$repo_root/_build/phase-11-policy"

if moonrun --policy "$repo_root/policies/deny.toml" "$wasm" \
  --list --justfile "$repo_root/tests/fixtures/phase-6/justfile" \
  >"$work/deny.stdout" 2>"$work/deny.stderr"; then
  release_fail "explicit deny policy allowed repository read"
fi
grep -Eq 'CapabilityUnavailable\(Environment\)|Sandbox policy blocked file read' \
  "$work/deny.stderr" || release_fail "explicit deny did not report a capability boundary"

cat >"$work/default.toml" <<'EOF'
[net]
dns = []
connect = []
bind = []
EOF
if moonrun --policy "$work/default.toml" "$wasm" \
  --list --justfile "$repo_root/tests/fixtures/phase-6/justfile" \
  >"$work/default.stdout" 2>"$work/default.stderr"; then
  release_fail "omitted capability sections did not deny by default"
fi
grep -Eq 'CapabilityUnavailable\(Environment\)|Sandbox policy blocked file read' \
  "$work/default.stderr" || release_fail "default deny did not report a capability boundary"

moonrun --policy "$repo_root/policies/inspect.toml" "$wasm" \
  --list --justfile "$repo_root/tests/fixtures/phase-6/justfile" \
  >"$work/inspect.stdout" 2>"$work/inspect.stderr"
grep -q '^Available recipes:$' "$work/inspect.stdout" || \
  release_fail "inspect policy did not allow read-only query"

moonrun --policy "$repo_root/policies/ci.toml" "$wasm" \
  --justfile "$repo_root/tests/fixtures/phase-8/line.justfile" build \
  >"$work/ci.stdout" 2>"$work/ci.stderr"
grep -q '^hello world$' "$work/ci.stdout" || \
  release_fail "CI policy did not allow the execution corpus"

moonrun --policy "$repo_root/policies/execute.toml" "$wasm" \
  --justfile "$repo_root/tests/fixtures/phase-8/line.justfile" build \
  >"$work/execute.stdout" 2>"$work/execute.stderr"
cmp -s "$work/ci.stdout" "$work/execute.stdout" || \
  release_fail "CI and explicit allow execution output differs"

echo "Phase 11 policies verified: explicit deny, default deny, inspect and controlled/full allow"
