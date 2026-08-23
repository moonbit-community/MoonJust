#!/bin/sh
set -eu

target=${1:?target is required}
output=$(moon test --target "$target" 2>&1) || {
  printf '%s\n' "$output"
  exit 1
}
printf '%s\n' "$output"
printf '%s\n' "$output" | grep -Eq 'Total tests: [1-9][0-9]*, passed: [0-9]+, failed: 0\.' || {
  echo "test-count gate: no passing tests were observed for target $target" >&2
  exit 1
}
