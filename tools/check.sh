#!/bin/sh
set -eu

moon fmt --check
./tools/checks/architecture.sh
./tools/upstream/verify_snapshot.sh
./tools/differential/self_test.sh
./tools/differential/real_smoke.sh
python3 ./tools/upstream/run_official_harness.py
python3 ./tools/upstream/evaluator_oracle.py --upstream ./_build/upstream/just-1.57.0/target/release/just
./tools/spikes/check_host_async.sh
./tools/spikes/check_ecosystem.sh
./tools/checks/inspect.sh
./tools/checks/query.sh
./tools/checks/hostfs.sh
./tools/checks/dotenv.sh
./tools/checks/invocation.sh
./tools/checks/workdir.sh
./tools/checks/environment.sh
./tools/checks/executor.sh
./tools/checks/runtime.sh
./tools/checks/compatibility.sh
./tools/checks/platform.sh
./tools/checks/release.sh
moon check --target all --warn-list +73
./tools/checks/test_target.sh native
./tools/checks/test_target.sh wasm
moon run --target native cmd/just -- --version
moon run --target wasm cmd/just -- --version
