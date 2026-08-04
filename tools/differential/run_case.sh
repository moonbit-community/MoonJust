#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 CASE_DIR RUN_DIR BINARY" >&2
  exit 2
fi

case_dir=$1
run_dir=$2
binary=$3

if [ -f "$case_dir/env.list" ]; then
  while IFS= read -r assignment || [ -n "$assignment" ]; do
    [ -z "$assignment" ] && continue
    # POSIX export accepts a quoted name=value assignment.
    # shellcheck disable=SC2163
    case "$assignment" in
      [A-Za-z_]*=*) export "$assignment" ;;
      *) echo "invalid environment assignment: $assignment" >&2; exit 2 ;;
    esac
  done <"$case_dir/env.list"
fi

set --
if [ -f "$case_dir/argv.txt" ]; then
  while IFS= read -r argument || [ -n "$argument" ]; do
    set -- "$@" "$argument"
  done <"$case_dir/argv.txt"
fi

cd "$run_dir"
exec "$binary" "$@" <"$case_dir/stdin"
