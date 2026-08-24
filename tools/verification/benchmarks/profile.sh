#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
workload=${1:-recipes-1000}
out="$repo_root/_build/performance/profile-$workload"
fixture="$out/justfile"

case "$workload" in
  recipes-1000|check|format)
    mode=recipes
    ;;
  dag-1000)
    mode=dag
    ;;
  *)
    echo "usage: $0 [recipes-1000|check|format|dag-1000]" >&2
    exit 2
    ;;
esac

mkdir -p "$out"
python3 - "$fixture" "$mode" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
mode = sys.argv[2]
if mode == "recipes":
    text = "".join(f"r{index:04d}:\n" for index in range(1000))
else:
    text = "root: " + " ".join(f"node{index:04d}" for index in range(999)) + "\n"
    text += "".join(f"node{index:04d}:\n" for index in range(999))
path.write_text(text, encoding="utf-8")
PY

case "$workload" in
  recipes-1000) arguments="--summary" ;;
  check) arguments="--fmt --check" ;;
  format) arguments="--fmt" ;;
  dag-1000) arguments="--dry-run root" ;;
esac

cd "$out"
# This is a manual trend profiler; host scheduling policy is intentionally
# observed by the operating system rather than enforced by a timing gate.
moon -C "$repo_root" run --frozen --release --target native --profile cmd/just -- \
  --justfile "$fixture" $arguments
