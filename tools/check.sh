#!/bin/sh
set -eu

case "${1:-}" in
  "") exec python3 ./tools/verification/runner.py verify ;;
  --release) exec python3 ./tools/verification/runner.py release ;;
  *) echo "usage: $0 [--release]" >&2; exit 2 ;;
esac
