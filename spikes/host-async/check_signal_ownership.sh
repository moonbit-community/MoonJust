#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if [ "$(uname -s)" != Linux ]; then
  echo "async signal ownership probe skipped: Linux-specific signal behavior"
  exit 0
fi

moon -C "$script_dir" build --target native signal_probe
probe="$script_dir/_build/native/debug/build/signal_probe/signal_probe.exe"
[ -x "$probe" ] || {
  echo "async signal ownership probe is missing: $probe" >&2
  exit 1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-async-signal.XXXXXX")
cleanup() {
  rm -f "$work"/stdout-* "$work"/stderr-*
  rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

total_conflicts=0
conflict_json=
for signal in HUP INT QUIT TERM; do
  conflicts=0
  attempt=1
  while [ "$attempt" -le 5 ]; do
    "$probe" >"$work/stdout-$signal-$attempt" 2>"$work/stderr-$signal-$attempt" &
    pid=$!
    sleep 0.05
    kill -"$signal" "$pid"
    status=0
    wait "$pid" || status=$?
    if [ "$status" -ne 0 ] || ! grep -qx custom-handler "$work/stdout-$signal-$attempt"; then
      conflicts=$((conflicts + 1))
    fi
    attempt=$((attempt + 1))
  done
  total_conflicts=$((total_conflicts + conflicts))
  separator=,
  [ -n "$conflict_json" ] || separator=
  conflict_json="$conflict_json$separator\"SIG$signal\":$conflicts"
done

status=passed
if [ "$total_conflicts" -ne 0 ]; then
  status=failed
fi
printf '{"async_version":"0.20.4","attempts_per_signal":5,"conflicts":{%s},"status":"%s"}\n' \
  "$conflict_json" "$status"
if [ "$total_conflicts" -ne 0 ]; then
  echo "application signal handler lost $total_conflicts ownership attempts" >&2
  exit 1
fi
