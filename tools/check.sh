#!/bin/sh
set -eu

moon fmt --check
./tools/upstream/verify_snapshot.sh
./tools/differential/self_test.sh
moon check --target all --warn-list +73
moon test --target native
moon test --target wasm
moon run --target native cmd/just -- --version
moon run --target wasm cmd/just -- --version
