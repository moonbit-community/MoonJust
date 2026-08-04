#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
cases_root="$repo_root/tests/differential/cases"
artifacts_root="$repo_root/_build/differential"
upstream=
candidate=

usage() {
  echo "usage: $0 --upstream BIN --candidate BIN [--cases DIR] [--artifacts DIR]" >&2
  exit 2
}

absolute_path() {
  path=$1
  directory=$(dirname -- "$path")
  base=$(basename -- "$path")
  printf '%s/%s\n' "$(CDPATH='' cd -- "$directory" && pwd)" "$base"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --upstream) [ "$#" -ge 2 ] || usage; upstream=$2; shift 2 ;;
    --candidate) [ "$#" -ge 2 ] || usage; candidate=$2; shift 2 ;;
    --cases) [ "$#" -ge 2 ] || usage; cases_root=$2; shift 2 ;;
    --artifacts) [ "$#" -ge 2 ] || usage; artifacts_root=$2; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$upstream" ] || usage
[ -n "$candidate" ] || usage
[ -x "$upstream" ] || { echo "upstream binary is not executable: $upstream" >&2; exit 2; }
[ -x "$candidate" ] || { echo "candidate binary is not executable: $candidate" >&2; exit 2; }
[ -d "$cases_root" ] || { echo "case directory not found: $cases_root" >&2; exit 2; }

upstream=$(absolute_path "$upstream")
candidate=$(absolute_path "$candidate")
cases_root=$(CDPATH='' cd -- "$cases_root" && pwd)
mkdir -p "$artifacts_root"
artifacts_root=$(CDPATH='' cd -- "$artifacts_root" && pwd)

snapshot_tree() {
  root=$1
  output=$2
  (
    cd "$root"
    find . -mindepth 1 -print | LC_ALL=C sort | while IFS= read -r path; do
      if [ -L "$path" ]; then
        printf 'link\t%s\t%s\n' "$path" "$(readlink "$path")"
      elif [ -d "$path" ]; then
        printf 'dir\t%s\n' "$path"
      elif [ -f "$path" ]; then
        if command -v sha256sum >/dev/null 2>&1; then
          digest=$(sha256sum "$path" | awk '{ print $1 }')
        else
          digest=$(shasum -a 256 "$path" | awk '{ print $1 }')
        fi
        printf 'file\t%s\t%s\n' "$path" "$digest"
      else
        printf 'other\t%s\n' "$path"
      fi
    done
  ) >"$output"
}

normalize() {
  input=$1
  output=$2
  run_root=$3
  sed "s|$run_root|<CASE_ROOT>|g" "$input" >"$output"
}

run_side() {
  side=$1
  binary=$2
  case_dir=$3
  artifact_dir=$4
  run_root="$artifact_dir/$side-root"
  mkdir -p "$run_root/home"
  if [ -d "$case_dir/tree" ]; then
    cp -R "$case_dir/tree/." "$run_root"
  fi

  set +e
  env -i \
    PATH="${PATH:-/usr/bin:/bin}" \
    HOME="$run_root/home" \
    LC_ALL=C \
    LANG=C \
    TZ=UTC \
    JUST_COLOR=never \
    sh "$script_dir/run_case.sh" "$case_dir" "$run_root" "$binary" \
    >"$artifact_dir/$side.stdout.raw" \
    2>"$artifact_dir/$side.stderr.raw"
  status=$?
  set -e

  printf '%s\n' "$status" >"$artifact_dir/$side.status"
  snapshot_tree "$run_root" "$artifact_dir/$side.tree"
  normalize "$artifact_dir/$side.stdout.raw" "$artifact_dir/$side.stdout" "$run_root"
  normalize "$artifact_dir/$side.stderr.raw" "$artifact_dir/$side.stderr" "$run_root"
}

same_artifacts() {
  artifact_dir=$1
  cmp -s "$artifact_dir/upstream.stdout" "$artifact_dir/candidate.stdout" &&
    cmp -s "$artifact_dir/upstream.stderr" "$artifact_dir/candidate.stderr" &&
    cmp -s "$artifact_dir/upstream.status" "$artifact_dir/candidate.status" &&
    cmp -s "$artifact_dir/upstream.tree" "$artifact_dir/candidate.tree"
}

total=0
matched=0
expected_differences=0
failures=0

for case_dir in "$cases_root"/*; do
  [ -d "$case_dir" ] || continue
  total=$((total + 1))
  case_name=$(basename -- "$case_dir")
  artifact_dir="$artifacts_root/$case_name"
  rm -rf -- "$artifact_dir"
  mkdir -p "$artifact_dir"

  expectation=$(tr -d '\r\n' <"$case_dir/expectation")
  run_side upstream "$upstream" "$case_dir" "$artifact_dir"
  run_side candidate "$candidate" "$case_dir" "$artifact_dir"

  if same_artifacts "$artifact_dir"; then
    observed=match
  else
    observed=difference
    diff -u "$artifact_dir/upstream.stdout" "$artifact_dir/candidate.stdout" \
      >"$artifact_dir/stdout.diff" || true
    diff -u "$artifact_dir/upstream.stderr" "$artifact_dir/candidate.stderr" \
      >"$artifact_dir/stderr.diff" || true
    diff -u "$artifact_dir/upstream.tree" "$artifact_dir/candidate.tree" \
      >"$artifact_dir/tree.diff" || true
  fi

  if [ "$expectation" = match ] && [ "$observed" = match ]; then
    matched=$((matched + 1))
    printf 'PASS  %s (match)\n' "$case_name"
  elif [ "$expectation" = difference ] && [ "$observed" = difference ]; then
    compat_id=$(tr -d '\r\n' <"$case_dir/compat-id")
    expected_differences=$((expected_differences + 1))
    printf 'XDIFF %s (%s)\n' "$case_name" "$compat_id"
  else
    failures=$((failures + 1))
    printf 'FAIL  %s (expected %s, observed %s)\n' \
      "$case_name" "$expectation" "$observed" >&2
  fi
done

printf 'total=%s matched=%s expected_differences=%s failures=%s\n' \
  "$total" "$matched" "$expected_differences" "$failures"
[ "$total" -gt 0 ] || { echo "no differential cases selected" >&2; exit 1; }
[ "$failures" -eq 0 ]
