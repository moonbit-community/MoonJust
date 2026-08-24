#!/bin/sh
set -eu
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
python3 "$repo_root/tools/runner.py" coverage --target native
python3 "$repo_root/tools/runner.py" coverage --target wasm
python3 "$repo_root/tools/runner.py" coverage --target merge
