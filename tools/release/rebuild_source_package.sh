#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/release_lib.sh"
repo_root=$(release_repo_root)
version=$(release_version "$repo_root")
archive=${1:-"$repo_root/_build/publish/moonbit-community-MoonJust-$version.zip"}
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-source-rebuild.XXXXXX")
export SOURCE_DATE_EPOCH=0
export ZERO_AR_DATE=1

cleanup() {
  case "$work" in
    "${TMPDIR:-/tmp}"/moonjust-source-rebuild.*) rm -rf -- "$work" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

[ -f "$archive" ] || release_fail "source package archive is missing: $archive"
python3 - "$archive" "$work" <<'PY'
import pathlib
import stat
import sys
import zipfile

archive = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive) as stream:
    names = [item.filename for item in stream.infolist()]
    if len(names) != len(set(names)):
        raise SystemExit("source package has duplicate entries")
    if len(names) != len({name.casefold() for name in names}):
        raise SystemExit("source package has case-insensitive duplicate entries")
    for name in names:
        path = pathlib.PurePosixPath(name)
        if (
            path.is_absolute()
            or pathlib.PureWindowsPath(name).drive
            or ".." in path.parts
            or "\\" in name
        ):
            raise SystemExit(f"unsafe source package entry: {name}")
    for item in stream.infolist():
        if not item.is_dir() and stat.S_IFMT(item.external_attr >> 16) not in {
            0,
            stat.S_IFREG,
        }:
            raise SystemExit(f"unsupported source package entry: {item.filename}")
    stream.extractall(target)
PY

python3 "$script_dir/copy_resolved_dependencies.py" \
  --manifest "$work/moon.mod" \
  --source "$repo_root/.mooncakes" \
  --target "$work/.mooncakes"
MOON_DEP_CACHE=off \
MOON_BUILD_CACHE=off \
  moon -C "$work" build --frozen --release --strip --target native cmd/just
MOON_DEP_CACHE=off \
MOON_BUILD_CACHE=off \
  moon -C "$work" build --frozen --release --strip --target wasm cmd/just

native="$work/_build/native/release/build/cmd/just/just.exe"
wasm="$work/_build/wasm/release/build/cmd/just/just.wasm"
[ -x "$native" ] || release_fail "cold source-package Native rebuild is missing"
[ -f "$wasm" ] || release_fail "cold source-package wasm1 rebuild is missing"
"$native" --version | grep -q "^moonjust $version " || \
  release_fail "cold source-package version differs"
moonrun --policy "$work/policies/deny.toml" "$wasm" -- --version | \
  grep -q "^moonjust $version " || release_fail "cold source-package wasm version differs"
"$native" --list --justfile "$work/tests/fixtures/phase-6/justfile" | \
  grep -q '^Available recipes:$' || release_fail "cold Native query corpus differs"
"$native" --justfile "$work/tests/fixtures/phase-8/line.justfile" build | \
  grep -q '^hello world$' || release_fail "cold Native execution corpus differs"
(cd "$work" && moonrun --policy policies/inspect.toml "$wasm" -- \
  --list --justfile tests/fixtures/phase-6/justfile) | \
  grep -q '^Available recipes:$' || release_fail "cold wasm query corpus differs"

echo "Phase 11 source package rebuilt from exact sources with caches disabled and corpus parity"
