#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/release_lib.sh"
repo_root=$(release_repo_root)
target="$repo_root/_build/phase-11-repeatable"
export SOURCE_DATE_EPOCH=0
export ZERO_AR_DATE=1
first=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-repeatable-first.XXXXXX")
second=

cleanup() {
  case "$first" in
    "${TMPDIR:-/tmp}"/moonjust-repeatable-first.*) rm -rf -- "$first" ;;
  esac
  case "$second" in
    "${TMPDIR:-/tmp}"/moonjust-repeatable-second.*) rm -rf -- "$second" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

reset_target() {
  case "$target" in
    "$repo_root"/_build/phase-11-repeatable) rm -rf -- "$target" ;;
    *) release_fail "refusing to reset unexpected repeatability target" ;;
  esac
}

build_once() {
  MOON_DEP_CACHE=off MOON_BUILD_CACHE=off moon build \
    --frozen --release --strip --target native --target-dir "$target" cmd/just
  cp "$target/native/release/build/cmd/just/just.exe" "$1/native"
  MOON_DEP_CACHE=off MOON_BUILD_CACHE=off moon build \
    --frozen --release --strip --target wasm --target-dir "$target" cmd/just
  cp "$target/wasm/release/build/cmd/just/just.wasm" "$1/wasm"
}

reset_target
build_once "$first"
reset_target
second=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-repeatable-second.XXXXXX")
case "$second" in
  "${TMPDIR:-/tmp}"/moonjust-repeatable-second.*) ;;
  *) release_fail "unexpected repeatability directory" ;;
esac
build_once "$second"
cmp -s "$first/native" "$second/native" || \
  release_fail "two clean Native builds from the same path differ"
cmp -s "$first/wasm" "$second/wasm" || \
  release_fail "two clean wasm builds from the same path differ"
rm -rf -- "$second"
second=
reset_target
echo "Phase 11 repeatability verified: two cache-disabled clean Native/wasm builds are byte-identical"
