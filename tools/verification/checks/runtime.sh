#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
fixture="$repo_root/tests/fixtures/runtime"
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-runtime.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

fail() {
  echo "Runtime gate failed: $1" >&2
  exit 1
}

check_parallel_output() {
  actual=$1
  [ "$(sort "$actual")" = "$(sort "$fixture/parallel.stdout")" ] ||
    fail "$2 parallel output did not contain each completed task exactly once"
}

moon test --target native src/scheduler
moon test --target native src/cache
moon test --target native src/runtime
moon test --target native src/host_native
moon test --target native src/host_process
moon test --target wasm src/scheduler
moon test --target wasm src/cache
moon test --target wasm src/runtime
moon test --target wasm src/host_wasm
moon test --target wasm src/host_process

if [ -z "${MOONJUST_NATIVE_CANDIDATE:-}" ]; then moon build cmd/just --target native >/dev/null; fi
if [ -z "${MOONJUST_WASM_CANDIDATE:-}" ]; then moon build cmd/just --target wasm >/dev/null; fi
cli_native="${MOONJUST_NATIVE_CANDIDATE:-$repo_root/_build/native/debug/build/cmd/just/just.exe}"
cli_wasm="${MOONJUST_WASM_CANDIDATE:-$repo_root/_build/wasm/debug/build/cmd/just/just.wasm}"

mkdir "$work/native" "$work/wasm"
cp "$fixture/justfile" "$work/native/justfile"
cp "$fixture/justfile" "$work/wasm/justfile"
printf 'one\n' >"$work/native/input"
printf 'one\n' >"$work/wasm/input"
printf 'a-one\n' >"$work/native/input-a"
printf 'b-one\n' >"$work/native/input-b"
mkdir "$work/native/input-dir" "$work/native/nested"
ln -s input "$work/native/input-link"
ln -s input-dir "$work/native/input-dir-link"

(
  cd "$work/native"
  "$cli_native" --unstable --jobs 2 root >parallel.stdout 2>parallel.stderr
)
check_parallel_output "$work/native/parallel.stdout" native

(
  cd "$work/native"
  "$cli_native" --unstable cached >first.stdout 2>first.stderr
  "$cli_native" --unstable cached >hit.stdout 2>hit.stderr
)
grep -qx 'cached-run' "$work/native/first.stdout" || fail "native cache miss did not execute"
[ ! -s "$work/native/hit.stdout" ] || fail "native cache hit executed the recipe"

printf 'two\n' >"$work/native/input"
(
  cd "$work/native"
  "$cli_native" --unstable cached >invalidated.stdout 2>invalidated.stderr
  "$cli_native" --unstable --no-cache cached >no-cache.stdout 2>no-cache.stderr
)
grep -qx 'cached-run' "$work/native/invalidated.stdout" || fail "input change did not invalidate cache"
grep -qx 'cached-run' "$work/native/no-cache.stdout" || fail "--no-cache did not bypass a hit"

rm "$work/native/artifact"
(
  cd "$work/native"
  "$cli_native" --unstable cached >missing-output.stdout 2>missing-output.stderr
)
grep -qx 'cached-run' "$work/native/missing-output.stdout" || fail "missing output did not invalidate cache"

(
  cd "$work/native"
  "$cli_native" --unstable --dry-run missing-input >dry-run.stdout 2>dry-run.stderr
)
[ ! -s "$work/native/dry-run.stdout" ] || fail "dry-run executed a missing-input recipe"
if (
  cd "$work/native"
  "$cli_native" --unstable missing-input >missing-input.stdout 2>missing-input.stderr
); then
  fail "missing cache input was accepted"
fi
[ ! -s "$work/native/missing-input.stdout" ] || fail "missing-input recipe started"
if (
  cd "$work/native"
  "$cli_native" --unstable directory-input >directory-input.stdout 2>directory-input.stderr
); then
  fail "directory cache input was accepted"
fi
if (
  cd "$work/native"
  "$cli_native" --unstable symlink-directory-input >symlink-directory.stdout 2>symlink-directory.stderr
); then
  fail "symlink-to-directory cache input was accepted"
fi

(
  cd "$work/native"
  "$cli_native" --unstable symlink-input >symlink-first.stdout 2>symlink-first.stderr
  "$cli_native" --unstable symlink-input >symlink-hit.stdout 2>symlink-hit.stderr
)
grep -qx 'symlink-run' "$work/native/symlink-first.stdout" || fail "symlink-to-file input did not execute"
[ ! -s "$work/native/symlink-hit.stdout" ] || fail "symlink-to-file input did not hit"
printf 'symlink-change\n' >"$work/native/input"
(
  cd "$work/native"
  "$cli_native" --unstable symlink-input >symlink-changed.stdout 2>symlink-changed.stderr
)
grep -qx 'symlink-run' "$work/native/symlink-changed.stdout" || fail "symlink target change did not invalidate cache"

(
  cd "$work/native"
  "$cli_native" --unstable multiple >multiple-first.stdout 2>multiple-first.stderr
  "$cli_native" --unstable multiple >multiple-hit.stdout 2>multiple-hit.stderr
)
grep -qx 'multiple-run' "$work/native/multiple-first.stdout" || fail "multiple input/output cache did not execute"
[ ! -s "$work/native/multiple-hit.stdout" ] || fail "multiple input/output cache did not hit"
printf 'b-two\n' >"$work/native/input-b"
(
  cd "$work/native"
  "$cli_native" --unstable multiple >multiple-changed.stdout 2>multiple-changed.stderr
  "$cli_native" --unstable directory-output >directory-output-first.stdout 2>directory-output-first.stderr
  "$cli_native" --unstable directory-output >directory-output-hit.stdout 2>directory-output-hit.stderr
  "$cli_native" --unstable cwd-output >cwd-output-first.stdout 2>cwd-output-first.stderr
  "$cli_native" --unstable cwd-output >cwd-output-hit.stdout 2>cwd-output-hit.stderr
)
grep -qx 'multiple-run' "$work/native/multiple-changed.stdout" || fail "second input change did not invalidate cache"
grep -qx 'directory-output-run' "$work/native/directory-output-first.stdout" || fail "directory output was rejected"
[ ! -s "$work/native/directory-output-hit.stdout" ] || fail "directory output did not hit"
grep -qx 'cwd-output-run' "$work/native/cwd-output-first.stdout" || fail "working-directory output did not execute"
[ -f "$work/native/nested/cwd-artifact" ] || fail "cache output did not resolve against recipe working directory"
[ ! -s "$work/native/cwd-output-hit.stdout" ] || fail "working-directory output did not hit"

(
  cd "$work/native"
  "$cli_native" --unstable dangling-output >dangling-first.stdout 2>dangling-first.stderr
)
grep -qx 'dangling-output-run' "$work/native/dangling-first.stdout" || fail "dangling-output fixture did not execute"
rm "$work/native/dangling-output"
ln -s missing-target "$work/native/dangling-output"
if (
  cd "$work/native"
  "$cli_native" --unstable dangling-output >dangling-retry.stdout 2>dangling-retry.stderr
); then
  fail "dangling output produced a cache hit"
fi
grep -qx 'dangling-output-run' "$work/native/dangling-retry.stdout" || fail "dangling output did not invalidate cache"

printf 'three\n' >"$work/native/input"
(
  cd "$work/native"
  "$cli_native" --unstable cached >contender-one.stdout 2>contender-one.stderr
) &
first_pid=$!
(
  cd "$work/native"
  "$cli_native" --unstable cached >contender-two.stdout 2>contender-two.stderr
) &
second_pid=$!
wait "$first_pid"
wait "$second_pid"
contender_runs=$(cat "$work/native/contender-one.stdout" "$work/native/contender-two.stdout" | grep -c '^cached-run$' || true)
[ "$contender_runs" -eq 1 ] || fail "two native processes did not serialize the same cache key"

# Kill both the cache-owning MoonJust process and its script, then prove that
# the OS lease is released and no partial manifest suppresses the retry.
(
  cd "$work/native"
  "$cli_native" --unstable crash >crash-first.stdout 2>crash-first.stderr
) &
crash_parent=$!
attempt=0
while [ ! -s "$work/native/crash-child.pid" ] && [ "$attempt" -lt 100 ]; do
  sleep 0.05
  attempt=$((attempt + 1))
done
[ -s "$work/native/crash-child.pid" ] || fail "crash fixture did not start"
crash_child=$(cat "$work/native/crash-child.pid")
kill -9 "$crash_parent" 2>/dev/null || true
kill -9 "$crash_child" 2>/dev/null || true
wait "$crash_parent" 2>/dev/null || true
(
  cd "$work/native"
  "$cli_native" --unstable crash >crash-retry.stdout 2>crash-retry.stderr
  "$cli_native" --unstable crash >crash-hit.stdout 2>crash-hit.stderr
)
grep -qx 'crash-recovered' "$work/native/crash-retry.stdout" || fail "crash retry did not execute"
[ ! -s "$work/native/crash-hit.stdout" ] || fail "crash retry did not publish a valid entry"

(
  cd "$work/native"
  "$cli_native" --clean >clean.stdout 2>clean.stderr
)
grep -Eq '^removed [1-9][0-9]* cache entr(y|ies)$' "$work/native/clean.stderr" || fail "--clean did not report removed entries"

(
  cd "$work/wasm"
  moonrun --policy "$repo_root/policies/execute.toml" "$cli_wasm" --unstable --jobs 2 root >parallel.stdout 2>parallel.stderr
  moonrun --policy "$repo_root/policies/execute.toml" "$cli_wasm" --unstable cached >first.stdout 2>first.stderr
  moonrun --policy "$repo_root/policies/execute.toml" "$cli_wasm" --unstable cached >hit.stdout 2>hit.stderr
)
check_parallel_output "$work/wasm/parallel.stdout" wasm
grep -qx 'cached-run' "$work/wasm/first.stdout" || fail "wasm cache miss did not execute"
[ ! -s "$work/wasm/hit.stdout" ] || fail "wasm cache hit executed the recipe"

echo "Runtime gate passed (bounded scheduler, crash recovery, two-process contention, Native/wasm cache CLI)"
