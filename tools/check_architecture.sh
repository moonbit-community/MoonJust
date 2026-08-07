#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
phase_packages="source diagnostic path host cli lexer syntax parser formatter semantic loader value builtin evaluator application"

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
      '#cfg|#external|extern[[:space:]]+"|native-stub|moonbitlang/async|async[[:space:]]+fn' \
      "$file"; then
      fail "target-specific implementation found in src/$package"
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

echo "architecture boundaries verified for fifteen core packages and one host adapter leaf"
