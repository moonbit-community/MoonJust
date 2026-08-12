#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)

python3 "$repo_root/tools/upstream/test_map.py"
python3 "$repo_root/tools/upstream/verify_manifest.py"
moon test --target native src/cli
moon test --target native src/application
moon test --target native src/formatter
moon test --target native src/loader
moon test --target wasm src/cli
moon test --target wasm src/application
moon test --target wasm src/formatter
moon test --target wasm src/loader

"$repo_root/tools/upstream/build_oracle.sh" >/dev/null
upstream="$repo_root/_build/upstream/just-1.57.0/source"
CARGO_TARGET_DIR="$repo_root/_build/upstream/just-1.57.0/target" \
  cargo test --manifest-path "$upstream/Cargo.toml" --locked tangle::tests

echo "Phase 10 compatibility gate passed (interactive, terminal, Markdown, complete inventory)"
