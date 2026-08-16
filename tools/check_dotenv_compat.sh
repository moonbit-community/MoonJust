#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-dotenv.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

oracle_target="$repo_root/_build/dotenvy-oracle"
CARGO_TARGET_DIR="$oracle_target" cargo build \
  --quiet \
  --locked \
  --manifest-path "$repo_root/tools/dotenvy_oracle/Cargo.toml"
oracle="$oracle_target/debug/moonjust-dotenvy-oracle"

compare() {
  name=$1
  fixture=$2
  KEY11=ambient "$oracle" <"$fixture" >"$work/$name.oracle"
  moon run --quiet --target native tools/dotenv_probe \
    <"$fixture" >"$work/$name.candidate" 2>"$work/$name.stderr"
  cmp "$work/$name.oracle" "$work/$name.candidate" || {
    diff -u "$work/$name.oracle" "$work/$name.candidate" || true
    echo "Dotenv differential failed: $name" >&2
    exit 1
  }
}

for fixture in basic substitution multiline; do
  compare "$fixture" "$repo_root/tests/fixtures/dotenv/$fixture.env"
done

printf 'CRLF=accepted\r\nSECOND=line\r\n' >"$work/crlf.env"
compare crlf "$work/crlf.env"

expect_invalid() {
  name=$1
  fixture=$2
  oracle_status=0
  candidate_status=0
  KEY11=ambient "$oracle" <"$fixture" \
    >"$work/$name.oracle.stdout" 2>"$work/$name.oracle.stderr" || oracle_status=$?
  moon run --quiet --target native tools/dotenv_probe <"$fixture" \
    >"$work/$name.stdout" 2>"$work/$name.stderr" || candidate_status=$?
  [ "$oracle_status" -ne 0 ] && [ "$candidate_status" -ne 0 ] || {
    echo "Dotenv differential failed: invalid fixture status differs: $name" >&2
    exit 1
  }
}

expect_invalid invalid "$repo_root/tests/fixtures/dotenv/invalid.env"
if grep -q 'top-secret' "$work/invalid.stderr"; then
  echo "Dotenv differential failed: diagnostic disclosed a value" >&2
  exit 1
fi
printf '\357\273\277BOM=rejected\n' >"$work/bom.env"
expect_invalid bom "$work/bom.env"

echo "Dotenv differential passed (6 fixtures, diagnostics redacted)"
