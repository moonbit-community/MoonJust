#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if [ "$(uname -s)" != Linux ]; then
  echo "async signal ownership probe skipped: Linux-specific sigwait behavior"
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

conflicts=0
attempt=1
while [ "$attempt" -le 5 ]; do
  "$probe" >"$work/stdout-$attempt" 2>"$work/stderr-$attempt" &
  pid=$!
  sleep 0.05
  kill -INT "$pid"
  status=0
  wait "$pid" || status=$?
  if [ "$status" -ne 0 ]; then
    conflicts=$((conflicts + 1))
  fi
  attempt=$((attempt + 1))
done

if [ "$conflicts" -eq 0 ]; then
  echo "async signal ownership limitation is stale: custom handler won all attempts" >&2
  exit 1
fi

printf '{"async_version":"0.20.4","attempts":5,"sigwait_conflicts":%s,"status":"unsupported"}\n' "$conflicts"
