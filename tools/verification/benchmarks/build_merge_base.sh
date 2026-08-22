#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)
base_ref=${MOONJUST_PERF_BASE:-HEAD^}
out=${MOONJUST_PERF_BASE_OUT:-"$repo_root/_build/performance/merge-base"}
if [ "$base_ref" = "0000000000000000000000000000000000000000" ]; then
  base_ref=HEAD^
fi
if ! git -C "$repo_root" cat-file -e "$base_ref^{commit}" 2>/dev/null; then
  echo "performance baseline error: commit is unavailable: $base_ref" >&2
  exit 1
fi
base=$(git -C "$repo_root" merge-base "$base_ref" HEAD)
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-perf-base.XXXXXX")

cleanup() {
  case "$work" in
    "${TMPDIR:-/tmp}"/moonjust-perf-base.*) rm -rf -- "$work" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

git -C "$repo_root" archive "$base" | tar -x -C "$work"
python3 "$repo_root/tools/release/copy_resolved_dependencies.py" \
  --manifest "$work/moon.mod" \
  --source "$repo_root/.mooncakes" \
  --target "$work/.mooncakes"
MOON_DEP_CACHE=off MOON_BUILD_CACHE=off moon -C "$work" build \
  --frozen --release --strip --target native cmd/just
MOON_DEP_CACHE=off MOON_BUILD_CACHE=off moon -C "$work" build \
  --frozen --release --strip --target wasm cmd/just

case "$out" in
  "$repo_root"/_build/performance/merge-base) rm -rf -- "$out" ;;
  *) echo "performance baseline error: unsafe output path $out" >&2; exit 1 ;;
esac
mkdir -p "$out"
cp "$work/_build/native/release/build/cmd/just/just.exe" "$out/just-native"
cp "$work/_build/wasm/release/build/cmd/just/just.wasm" "$out/just.wasm"
chmod 755 "$out/just-native"
python3 - "$out/metadata.json" "$base" "$out/just-native" "$out/just.wasm" <<'PY'
from pathlib import Path
import hashlib
import json
import subprocess
import sys

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

output, commit, native, wasm = map(Path, sys.argv[1:])
record = {
    "schema_version": 1,
    "commit": str(commit),
    "moon": subprocess.run(
        ["moon", "version", "--all"], check=True, capture_output=True, text=True
    ).stdout.strip(),
    "native": {"bytes": native.stat().st_size, "sha256": digest(native)},
    "wasm1": {"bytes": wasm.stat().st_size, "sha256": digest(wasm)},
}
output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
echo "merge-base performance artifacts built from $base"
