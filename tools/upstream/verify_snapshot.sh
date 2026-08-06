#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

python3 "$script_dir/test_map.py"
python3 "$script_dir/verify_manifest.py"
echo "compatibility snapshot verified"
