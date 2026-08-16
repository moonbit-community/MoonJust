#!/bin/sh
set -eu

moon fmt --check
./tools/check_architecture.sh
./tools/upstream/verify_snapshot.sh
./tools/differential/self_test.sh
./tools/differential/real_smoke.sh
python3 ./tools/upstream/run_official_harness.py
python3 ./tools/upstream/evaluator_oracle.py --upstream ./_build/upstream/just-1.57.0/target/release/just
./tools/spikes/check_host_async.sh
./tools/spikes/check_ecosystem.sh
./tools/check_inspect_policy.sh
./tools/check_query_compat.sh
./tools/check_hostfs_policy.sh
./tools/check_dotenv_compat.sh
./tools/check_invocation_compat.sh
./tools/check_workdir_compat.sh
./tools/check_environment_compat.sh
./tools/check_executor.sh
./tools/check_runtime.sh
./tools/check_compatibility.sh
./tools/check_platform.sh
./tools/check_release.sh
moon check --target all --warn-list +73
./tools/test_with_count.sh native
./tools/test_with_count.sh wasm
moon run --target native cmd/just -- --version
moon run --target wasm cmd/just -- --version
