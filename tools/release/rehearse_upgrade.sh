#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/release_lib.sh"
repo_root=$(release_repo_root)
out_root=${MOONJUST_RELEASE_OUT:-"$repo_root/_build/release"}
platform=${MOONJUST_RELEASE_PLATFORM:-$(release_platform)}
export SOURCE_DATE_EPOCH=0
export ZERO_AR_DATE=1
candidate=$(
  MOONJUST_RELEASE_PLATFORM="$platform" \
    MOONJUST_RELEASE_OUT="$out_root/candidate" \
    "$script_dir/build_artifacts.sh"
)

case "$platform" in
  windows-*) extension=.zip ;;
  *) extension=.tar.gz ;;
esac
previous_root=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-previous-source.XXXXXX")
previous_out="$out_root/previous"

cleanup() {
  case "$previous_root" in
    "${TMPDIR:-/tmp}"/moonjust-previous-source.*) rm -rf -- "$previous_root" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$previous_root"
git archive fedf99f7a6a5f99e2b559b07931d009e162fbfce | \
  tar -x -C "$previous_root"
case "$previous_out" in
  "$out_root"/previous) rm -rf -- "$previous_out" ;;
  *) release_fail "refusing to reset unexpected previous-release path" ;;
esac
mkdir -p "$previous_out"
python3 "$script_dir/copy_resolved_dependencies.py" \
  --manifest "$previous_root/moon.mod" \
  --source "$repo_root/.mooncakes" \
  --target "$previous_root/.mooncakes"
MOON_DEP_CACHE=off \
MOON_BUILD_CACHE=off \
  moon -C "$previous_root" build --frozen --release --strip --target native cmd/just >/dev/null
previous_stage="$previous_out/manual"
mkdir -p "$previous_stage"
previous_binary="$previous_root/_build/native/release/build/cmd/just/just.exe"
if [ "$extension" = .zip ]; then
  cp "$previous_binary" "$previous_stage/just.exe"
  python3 "$script_dir/create_archive.py" \
    --source "$previous_stage" --output "$previous_out/moonjust-0.7.0-alpha-$platform.zip"
else
  cp "$previous_binary" "$previous_stage/just"
  chmod 755 "$previous_stage/just"
  python3 "$script_dir/create_archive.py" \
    --source "$previous_stage" --output "$previous_out/moonjust-0.7.0-alpha-$platform.tar.gz"
fi
previous=$(find "$previous_out" -maxdepth 1 -type f -name "*$extension" | head -1)
[ -n "$previous" ] || release_fail "previous Phase 10 archive is missing"

python3 "$script_dir/rehearse_upgrade.py" \
  --repo "$repo_root" \
  --previous "$previous" \
  --candidate "$candidate"
