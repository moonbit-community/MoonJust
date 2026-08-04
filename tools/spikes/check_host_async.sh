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
