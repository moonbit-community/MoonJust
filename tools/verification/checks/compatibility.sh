#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/../../.." && pwd)

python3 "$repo_root/tools/upstream/test_map.py"
python3 "$repo_root/tools/upstream/verify_manifest.py"
if [ -n "${MOONJUST_NATIVE_CANDIDATE:-}" ] || [ -n "${MOONJUST_WASM_CANDIDATE:-}" ]; then
  [ -n "${MOONJUST_NATIVE_CANDIDATE:-}" ] && [ -n "${MOONJUST_WASM_CANDIDATE:-}" ] || {
    echo "both explicit compatibility candidates are required" >&2
    exit 1
  }
  python3 "$repo_root/tools/upstream/run_official_harness.py" \
    --native-candidate "$MOONJUST_NATIVE_CANDIDATE" \
    --wasm-candidate "$MOONJUST_WASM_CANDIDATE"
else
  python3 "$repo_root/tools/upstream/run_official_harness.py"
fi
moon test --target native internal/cli
moon test --target native internal/application
moon test --target native internal/formatter
moon test --target native internal/loader
moon test --target wasm internal/cli
moon test --target wasm internal/application
moon test --target wasm internal/formatter
moon test --target wasm internal/loader

if [ -z "${MOONJUST_ORACLE_CANDIDATE:-}" ]; then "$repo_root/tools/upstream/build_oracle.sh" >/dev/null; fi
upstream="$repo_root/_build/upstream/just-1.57.0/source"
CARGO_TARGET_DIR="$repo_root/_build/upstream/just-1.57.0/target" \
  cargo test --manifest-path "$upstream/Cargo.toml" --locked tangle::tests

echo "Compatibility gate passed (strict pinned differential and inventory consistency)"
