#!/bin/sh
set -eu

expected_tag=1.57.0
expected_commit=e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f
expected_lock_sha256=907adacb2b2a3db5ed6be6f130e18aec6f869bdc8b5dc64a9ecb98484fbfb550
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
cache_root=${MOONJUST_ORACLE_CACHE:-$repo_root/_build/upstream/just-1.57.0}
checkout="$cache_root/source"
binary="$cache_root/target/release/just"
case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*) binary="$cache_root/target/release/just.exe" ;;
esac

fail() {
  echo "upstream oracle error: $1" >&2
  exit 1
}

oracle_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX \
    -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    -u GIT_COMMON_DIR -u GIT_NAMESPACE git -C "$checkout" "$@"
}

mkdir -p "$cache_root"

if [ ! -d "$checkout/.git" ]; then
  temporary_clone="$cache_root/source.clone"
  rm -rf -- "$temporary_clone"
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX \
    -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    -u GIT_COMMON_DIR -u GIT_NAMESPACE \
    git clone --quiet --branch "$expected_tag" --depth 1 \
    https://github.com/casey/just.git "$temporary_clone"
  mv -- "$temporary_clone" "$checkout"
fi

[ "$(oracle_git rev-parse --is-inside-work-tree)" = true ] || \
  fail "oracle checkout is not a git worktree"

actual_commit=$(oracle_git rev-parse "refs/tags/$expected_tag^{commit}")
[ "$actual_commit" = "$expected_commit" ] || \
  fail "expected peeled tag commit $expected_commit, found $actual_commit"

lock="$checkout/Cargo.lock"
[ -f "$lock" ] || fail "Cargo.lock is missing from the pinned checkout"
if command -v sha256sum >/dev/null 2>&1; then
  actual_lock_sha256=$(sha256sum "$lock" | awk '{ print $1 }')
else
  actual_lock_sha256=$(shasum -a 256 "$lock" | awk '{ print $1 }')
fi
[ "$actual_lock_sha256" = "$expected_lock_sha256" ] || \
  fail "Cargo.lock SHA-256 is $actual_lock_sha256, expected $expected_lock_sha256"

command -v cargo >/dev/null 2>&1 || fail "cargo is required to build the pinned oracle"
CARGO_TARGET_DIR="$cache_root/target" \
  cargo build --quiet --release --manifest-path "$checkout/Cargo.toml" --locked
[ -f "$binary" ] || fail "cargo did not produce $binary"

version=$($binary --version)
case "$version" in
  *"just $expected_tag"*) ;;
  *) fail "oracle version output is not just $expected_tag: $version" ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
  binary_sha256=$(sha256sum "$binary" | awk '{ print $1 }')
else
  binary_sha256=$(shasum -a 256 "$binary" | awk '{ print $1 }')
fi

printf '%s\n' \
  "source=$checkout" \
  "tag=$expected_tag" \
  "commit=$actual_commit" \
  "cargo_lock_sha256=$actual_lock_sha256" \
  "binary=$binary" \
  "binary_sha256=$binary_sha256" \
  "version=$version"
