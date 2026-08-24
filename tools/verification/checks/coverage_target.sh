#!/bin/sh
set -eu
repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)
exec python3 "$repo_root/tools/quality/collect_coverage.py" --repo "$repo_root" --target "$1" --output "$repo_root/_build/coverage"
