#!/bin/sh
set -eu

moon fmt --check
./tools/check_architecture.sh
./tools/upstream/verify_snapshot.sh
./tools/differential/self_test.sh
./tools/spikes/check_host_async.sh
./tools/spikes/check_ecosystem.sh
moon check --target all --warn-list +73
moon test --target native
moon test --target wasm
moon run --target native cmd/just -- --version
moon run --target wasm cmd/just -- --version
