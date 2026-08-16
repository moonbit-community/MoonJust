#!/bin/sh
set -eu

if command -v moonx >/dev/null 2>&1; then
  moonx --version
  exit 0
fi

moon_path=$(command -v moon) || {
  echo "Release CI setup failed: moon is not installed" >&2
  exit 1
}
moon_dir=$(dirname -- "$moon_path")
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    cp "$moon_path" "$moon_dir/moonx.exe"
    ;;
  *)
    ln -s "$moon_path" "$moon_dir/moonx"
    ;;
esac
hash -r
moonx --version
