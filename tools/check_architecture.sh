#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
phase_packages="source diagnostic path host cli lexer syntax parser formatter semantic loader value builtin evaluator environment application"

fail() {
  echo "architecture boundary error: $1" >&2
  exit 1
}

for package in $phase_packages; do
  package_dir="$repo_root/src/$package"
  [ -f "$package_dir/moon.pkg" ] || fail "missing src/$package/moon.pkg"
  [ -f "$package_dir/pkg.generated.mbti" ] || \
    fail "missing src/$package/pkg.generated.mbti"

  for file in "$package_dir"/*.mbt "$package_dir/moon.pkg"; do
    [ -f "$file" ] || continue
    if grep -nE \
      '#cfg|#external|extern[[:space:]]+"|native-stub|moonbitlang/async' \
      "$file"; then
      fail "target-specific implementation found in src/$package"
    fi
    if [ "$package" != host ] && grep -nE 'async[[:space:]]+fn' "$file"; then
      fail "async implementation found in src/$package"
    fi
  done
done

pure_packages="source diagnostic path cli lexer syntax parser formatter semantic value builtin"
for package in $pure_packages; do
  if grep -nE 'src/host(_native|_wasm)?' "$repo_root/src/$package/moon.pkg"; then
    fail "src/$package imports a host package"
  fi
done

if grep -nE 'src/host_(native|wasm)' "$repo_root/src/host/moon.pkg"; then
  fail "host contracts import a concrete host adapter"
fi

[ -f "$repo_root/src/host_native/moon.pkg" ] || fail "missing native host adapter package"
[ -f "$repo_root/src/host_native/pkg.generated.mbti" ] || fail "missing native host adapter interface"
if grep -nE 'src/(semantic|evaluator|builtin|parser|formatter)' "$repo_root/src/host_native/moon.pkg"; then
  fail "native host adapter imports core implementation packages"
fi

[ -f "$repo_root/src/host_wasm/moon.pkg" ] || fail "missing Wasm host adapter package"
[ -f "$repo_root/src/host_wasm/pkg.generated.mbti" ] || fail "missing Wasm host adapter interface"
if grep -nE 'Host(Process|Env|Clock|Random|Terminal|Signal)|write_bytes_to_file' \
  "$repo_root/src/host_wasm"/*.mbt; then
  fail "Wasm inspect adapter exposes a forbidden capability"
fi
grep -Eq '^write = \[\]$' "$repo_root/policies/inspect.toml" || \
  fail "Wasm inspect policy grants filesystem writes"
grep -Eq '^spawn = false$' "$repo_root/policies/inspect.toml" || \
  fail "Wasm inspect policy grants process spawn"

transaction_dir="$repo_root/src/host_wasm/transaction"
[ -f "$transaction_dir/moon.pkg" ] || fail "missing Wasm transaction adapter package"
grep -Eq '^supported_targets = "-all\+wasm"$' "$transaction_dir/moon.pkg" || \
  fail "Wasm transaction adapter is not wasm1-only"
if grep -nE 'Host(Process|Env|Clock|Terminal|Signal)|wasi_snapshot_preview1' \
  "$transaction_dir"/*.mbt "$transaction_dir/moon.pkg"; then
  fail "Wasm transaction adapter crosses its capability boundary"
fi

echo "architecture boundaries verified for sixteen core packages and host adapter leaves"
