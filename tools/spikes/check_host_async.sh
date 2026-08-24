#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../.." && pwd)
spike="$repo_root/spikes/host-async"

case "$(uname -s)" in
  Darwin|Linux) ;;
  *)
    echo "host async spike skipped: Unix /bin/sh contract only"
    exit 0
    ;;
esac

moon -C "$spike" fmt --check
moon -C "$spike" check --target native --warn-list +73
moon -C "$spike" check --target wasm --warn-list +73
moon -C "$spike" test --target native
moon -C "$spike" test --target wasm
"$spike/check_signal_ownership.sh"

moon -C "$spike" build --target native process_lifecycle
lifecycle="$spike/_build/native/debug/build/process_lifecycle/process_lifecycle.exe"
evidence="$repo_root/_build/host-async/process-lifecycle.jsonl"
if [ "$(uname -s)" = Linux ]; then
  python3 "$spike/check_process_lifecycle.py" \
    --executable "$lifecycle" \
    --async-root "$spike/.mooncakes/moonbitlang/async" \
    --output "$evidence" \
    --assert-linux
else
  python3 "$spike/check_process_lifecycle.py" \
    --executable "$lifecycle" \
    --async-root "$spike/.mooncakes/moonbitlang/async" \
    --output "$evidence"
fi

if [ -z "${MOONJUST_NATIVE_CANDIDATE:-}" ]; then moon -C "$repo_root" build --target native cmd/just; fi
moonjust="${MOONJUST_NATIVE_CANDIDATE:-$repo_root/_build/native/debug/build/cmd/just/just.exe}"
direct_child_evidence="$repo_root/_build/host-async/moonjust-direct-child.jsonl"
python3 "$spike/check_moonjust_process_lifecycle.py" \
  --executable "$moonjust" \
  --output "$direct_child_evidence"
