#!/bin/sh
set -eu

expected_commit=e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f
expected_count=2417
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
output="$repo_root/tests/upstream/just-1.57.0/test-list.txt"
temporary_root=

cleanup() {
  if [ -n "$temporary_root" ] && [ -d "$temporary_root" ]; then
    rm -rf -- "$temporary_root"
  fi
}
trap cleanup EXIT HUP INT TERM

if [ "$#" -gt 1 ]; then
  echo "usage: $0 [JUST_CHECKOUT]" >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  checkout=$1
else
  temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-upstream.XXXXXX")
  checkout="$temporary_root/just"
  git clone --quiet --depth 1 --branch 1.57.0 \
    https://github.com/casey/just.git "$checkout"
fi

actual_commit=$(git -C "$checkout" rev-parse HEAD)
if [ "$actual_commit" != "$expected_commit" ]; then
  echo "expected just commit $expected_commit, found $actual_commit" >&2
  exit 1
fi

generated=$(mktemp "${TMPDIR:-/tmp}/moonjust-tests.XXXXXX")
trap 'rm -f -- "$generated"; cleanup' EXIT HUP INT TERM

(
  cd "$checkout"
  cargo test -- --list 2>/dev/null
) | awk '/: test$/ { sub(/: test$/, ""); print }' | LC_ALL=C sort >"$generated"

actual_count=$(wc -l <"$generated" | tr -d ' ')
if [ "$actual_count" != "$expected_count" ]; then
  echo "expected $expected_count test registrations, found $actual_count" >&2
  exit 1
fi

mkdir -p "$(dirname -- "$output")"
mv -- "$generated" "$output"
trap cleanup EXIT HUP INT TERM

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$output"
else
  shasum -a 256 "$output"
fi
