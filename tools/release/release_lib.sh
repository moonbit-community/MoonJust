#!/bin/sh

release_fail() {
  echo "Release release error: $1" >&2
  exit 1
}

release_repo_root() {
  release_script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  CDPATH='' cd -- "$release_script_dir/../.." && pwd
}

release_version() {
  sed -n 's/^version = "\([^"]*\)"$/\1/p' "$1/moon.mod"
}

release_commit() {
  git -C "$1" rev-parse HEAD
}

release_platform() {
  release_uname_s=$(uname -s)
  release_uname_m=$(uname -m)
  case "$release_uname_s" in
    Linux) release_os=linux ;;
    Darwin) release_os=macos ;;
    MINGW*|MSYS*|CYGWIN*) release_os=windows ;;
    *) release_fail "unsupported release operating system: $release_uname_s" ;;
  esac
  case "$release_uname_m" in
    x86_64|amd64|AMD64) release_arch=x86_64 ;;
    arm64|aarch64) release_arch=aarch64 ;;
    *) release_fail "unsupported release architecture: $release_uname_m" ;;
  esac
  printf '%s-%s\n' "$release_os" "$release_arch"
}

release_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}
