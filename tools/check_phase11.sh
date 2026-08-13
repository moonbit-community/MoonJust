#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
release_dir="$repo_root/tools/release"
phase="$repo_root/compat/phase-11.toml"
version=$(sed -n 's/^version = "\([^"]*\)"$/\1/p' "$repo_root/moon.mod")
work=$(mktemp -d "${TMPDIR:-/tmp}/moonjust-phase11.XXXXXX")
export SOURCE_DATE_EPOCH=0
export ZERO_AR_DATE=1

fail() {
  echo "Phase 11 gate failed: $1" >&2
  exit 1
}

cleanup() {
  case "$work" in
    "${TMPDIR:-/tmp}"/moonjust-phase11.*) rm -rf -- "$work" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

[ "$version" = "0.7.0-alpha.1" ] || fail "module version differs from Phase 11 identity"
grep -q '^coordinate = "moonbit-community/MoonJust/cmd/just@0.7.0-alpha.1"$' "$phase" || \
  fail "MoonX coordinate differs"
for required in API.mbt.md docs/API.md docs/RELEASE_POLICY.md LICENSE NOTICE README.mbt.md SECURITY.md CHANGELOG.md; do
  [ -s "$repo_root/$required" ] || fail "required publication file is missing: $required"
done

moon check --target all --warn-list +73
python3 "$release_dir/check_dependencies.py"
moon package
source_archive="$repo_root/_build/package/moonbit-community-MoonJust-$version.zip"
[ -f "$source_archive" ] || source_archive="$repo_root/_build/publish/moonbit-community-MoonJust-$version.zip"
[ -f "$source_archive" ] || fail "moon package archive is missing"
python3 "$release_dir/verify_source_package.py" --archive "$source_archive"
moon build --frozen --release --strip --target native cmd/just
moon build --frozen --release --strip --target wasm cmd/just
"$release_dir/rebuild_source_package.sh" "$source_archive"
"$release_dir/check_repeatable_build.sh"

"$release_dir/check_policies.sh"

platform=$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)
case "$platform" in
  darwin-arm64) platform=macos-aarch64 ;;
  darwin-x86_64) platform=macos-x86_64 ;;
  linux-arm64|linux-aarch64) platform=linux-aarch64 ;;
  linux-x86_64) platform=linux-x86_64 ;;
  mingw*|msys*|cygwin*) platform=windows-x86_64 ;;
esac
archive=$(MOONJUST_RELEASE_PLATFORM="$platform" "$release_dir/build_artifacts.sh")
python3 "$release_dir/verify_bundle.py" \
  --repo "$repo_root" --archive "$archive" --platform "$platform"
python3 "$release_dir/check_tamper_resistance.py" \
  --repo "$repo_root" --archive "$archive" --platform "$platform"

python3 "$release_dir/check_moonx_asset.py" \
  --repo "$repo_root" \
  --registry "$repo_root/_build/release" \
  --coordinate "moonbit-community/MoonJust/cmd/just@$version"

MOONJUST_RELEASE_PLATFORM="$platform" \
  MOONJUST_RELEASE_OUT="$repo_root/_build/phase-11-upgrade" \
  "$release_dir/rehearse_upgrade.sh"

python3 -m py_compile "$release_dir"/*.py
echo "Phase 11 release engineering gate passed: metadata, policies, package, artifacts, MoonX and supply chain"
