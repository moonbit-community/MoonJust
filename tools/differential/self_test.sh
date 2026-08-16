#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
temporary_root=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-diff-self-test.XXXXXX")

cleanup() {
  rm -rf -- "$temporary_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$temporary_root/cases/01-match/tree" "$temporary_root/cases/02-diff/tree"
cat >"$temporary_root/cases.toml" <<'EOF'
schema_version = 2
upstream = "self-test"

[[case]]
id = "MJ-COMPAT-SELF-MATCH"
directory = "01-match"
owner_phase = 0
status = "match"
compare = ["status", "stdout", "stderr", "tree"]
upstream_tests = []

[[case]]
id = "MJ-COMPAT-SELF-DIFF"
directory = "02-diff"
owner_phase = 0
status = "expected-difference"
compare = ["status", "stdout", "stderr", "tree"]
upstream_tests = []
allowed_difference = "product-identity"
EOF
: >"$temporary_root/cases/01-match/argv.txt"
: >"$temporary_root/cases/01-match/stdin"
: >"$temporary_root/cases/01-match/env.list"
printf 'match\n' >"$temporary_root/cases/01-match/expectation"
printf 'seed\n' >"$temporary_root/cases/01-match/tree/input.txt"

printf '%s\n' --different >"$temporary_root/cases/02-diff/argv.txt"
: >"$temporary_root/cases/02-diff/stdin"
: >"$temporary_root/cases/02-diff/env.list"
printf 'difference\n' >"$temporary_root/cases/02-diff/expectation"
printf 'MJ-COMPAT-SELF-TEST\n' >"$temporary_root/cases/02-diff/compat-id"

# The quoted expressions are written to the fixture scripts, not expanded here.
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' \
  'if [ "${1:-}" = --different ]; then echo upstream; else echo same; fi' \
  >"$temporary_root/upstream"
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' \
  'if [ "${1:-}" = --different ]; then echo candidate; else echo same; fi' \
  >"$temporary_root/candidate"
chmod +x "$temporary_root/upstream" "$temporary_root/candidate"

"$script_dir/run.sh" \
  --upstream "$temporary_root/upstream" \
  --candidate "$temporary_root/candidate" \
  --manifest "$temporary_root/cases.toml" \
  --cases "$temporary_root/cases" \
  --artifacts "$temporary_root/artifacts"
