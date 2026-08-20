#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
. "$script_dir/release_lib.sh"
repo_root=$(release_repo_root)
version=$(release_version "$repo_root")
commit=$(release_commit "$repo_root")
platform=${MOONJUST_RELEASE_PLATFORM:-$(release_platform)}
out_root=${MOONJUST_RELEASE_OUT:-"$repo_root/_build/release"}
actual_platform=$(release_platform)
target_dir="$out_root/build"
stage="$out_root/stage/moonjust-$version-$platform"
bundle="$out_root/moonjust-$version-$platform"
export SOURCE_DATE_EPOCH=0
export ZERO_AR_DATE=1

[ -n "$version" ] || release_fail "moon.mod has no version"
if [ "${MOONJUST_REQUIRE_CLEAN:-0}" = 1 ] && \
  [ -n "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]; then
  release_fail "release checkout is not clean"
fi
case "$platform" in
  linux-*|macos-*|windows-*) ;;
  *) release_fail "invalid release platform: $platform" ;;
esac
[ "$platform" = "$actual_platform" ] || \
  release_fail "release platform $platform differs from builder $actual_platform"
case "$target_dir" in
  "$out_root"/build) rm -rf -- "$target_dir" ;;
  *) release_fail "refusing to reset unexpected release build path" ;;
esac
case "$stage" in
  "$out_root"/stage/moonjust-*) rm -rf -- "$stage" ;;
  *) release_fail "refusing to reset unexpected staging path: $stage" ;;
esac

MOON_DEP_CACHE=off MOON_BUILD_CACHE=off moon build --frozen --release --strip \
  --target native --target-dir "$target_dir" cmd/just
native_source="$target_dir/native/release/build/cmd/just/just.exe"
[ -f "$native_source" ] || release_fail "native release executable is missing"

mkdir -p "$stage"
if [ "${platform%%-*}" = windows ]; then
  native_name=just.exe
  archive="$bundle.zip"
else
  native_name=just
  archive="$bundle.tar.gz"
fi
cp "$native_source" "$stage/$native_name"
chmod 755 "$stage/$native_name"
for release_file in LICENSE NOTICE README.mbt.md SECURITY.md CHANGELOG.md; do
  cp "$repo_root/$release_file" "$stage/$release_file"
done

python3 "$script_dir/generate_supply_chain.py" \
  --repo "$repo_root" \
  --artifact "$stage/$native_name" \
  --target "$platform" \
  --out "$stage"
python3 "$script_dir/verify_supply_chain.py" \
  --repo "$repo_root" \
  --artifact "$stage/$native_name" \
  --target "$platform" \
  --sbom "$stage/sbom.cdx.json" \
  --provenance "$stage/provenance.intoto.json" >&2

native_digest=$(release_sha256 "$stage/$native_name")
printf '%s  %s\n' "$native_digest" "$native_name" >"$stage/SHA256SUMS"
python3 "$script_dir/create_archive.py" --source "$stage" --output "$archive"
archive_digest=$(release_sha256 "$archive")
printf '%s  %s\n' "$archive_digest" "$(basename "$archive")" >"$archive.sha256"

if [ -n "${MOONJUST_WASM_ASSET:-}" ]; then
  wasm_input=$MOONJUST_WASM_ASSET
  case "$wasm_input" in
    /*) wasm_source=$wasm_input ;;
    [A-Za-z]:[\\/]* )
      if ! command -v cygpath >/dev/null 2>&1; then
        release_fail "cygpath is required to normalize a Windows wasm asset path"
      fi
      wasm_source=$(cygpath -u -- "$wasm_input") ;;
    *) release_fail "MOONJUST_WASM_ASSET must be an absolute path" ;;
  esac
  [ -f "$wasm_source" ] || release_fail "downloaded wasm1 release asset is missing"
else
  MOON_DEP_CACHE=off MOON_BUILD_CACHE=off moon build --frozen --release --strip \
    --target wasm --target-dir "$target_dir" cmd/just
  wasm_source="$target_dir/wasm/release/build/cmd/just/just.wasm"
  [ -f "$wasm_source" ] || release_fail "wasm1 release executable is missing"
fi
wasm_dir="$out_root/assets/moonbit-community/MoonJust@$version/cmd/just"
case "$wasm_dir" in
  "$out_root"/assets/moonbit-community/MoonJust@*/cmd/just) rm -rf -- "$wasm_dir" ;;
  *) release_fail "refusing to reset unexpected wasm asset path: $wasm_dir" ;;
esac
mkdir -p "$wasm_dir"
wasm_asset="$wasm_dir/just.wasm"
cp "$wasm_source" "$wasm_asset"
wasm_digest=$(release_sha256 "$wasm_asset")
printf '%s  just.wasm\n' "$wasm_digest" >"$wasm_asset.sha256"
python3 "$script_dir/generate_supply_chain.py" \
  --repo "$repo_root" \
  --artifact "$wasm_asset" \
  --target wasm1 \
  --out "$wasm_dir"
python3 "$script_dir/verify_supply_chain.py" \
  --repo "$repo_root" \
  --artifact "$wasm_asset" \
  --target wasm1 \
  --sbom "$wasm_dir/sbom.cdx.json" \
  --provenance "$wasm_dir/provenance.intoto.json" >&2

cat >"$out_root/build-$platform.json" <<EOF
{
  "schema_version": 1,
  "version": "$version",
  "commit": "$commit",
  "platform": "$platform",
  "native_sha256": "$native_digest",
  "archive": "$(basename "$archive")",
  "archive_sha256": "$archive_digest",
  "wasm_asset": "assets/moonbit-community/MoonJust@$version/cmd/just/just.wasm",
  "wasm_sha256": "$wasm_digest",
  "wasm_sbom": "assets/moonbit-community/MoonJust@$version/cmd/just/sbom.cdx.json",
  "wasm_provenance": "assets/moonbit-community/MoonJust@$version/cmd/just/provenance.intoto.json"
}
EOF

printf '%s\n' "$archive"
