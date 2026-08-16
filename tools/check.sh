#!/bin/sh
set -eu

moon fmt --check
./tools/check_architecture.sh
./tools/upstream/verify_snapshot.sh
./tools/differential/self_test.sh
./tools/differential/real_smoke.sh
python3 ./tools/upstream/run_official_harness.py
python3 ./tools/upstream/phase5_oracle.py --upstream ./_build/upstream/just-1.57.0/target/release/just
./tools/spikes/check_host_async.sh
./tools/spikes/check_ecosystem.sh
./tools/check_phase6_inspect.sh
./tools/check_phase6_oracle.sh
./tools/check_phase7_hostfs.sh
./tools/check_phase7_dotenv.sh
./tools/check_phase7_invocation.sh
./tools/check_phase7_workdir.sh
./tools/check_phase7_environment.sh
./tools/check_phase8_executor.sh
./tools/check_phase9_runtime.sh
./tools/check_phase10.sh
./tools/check_phase10_platform.sh
./tools/check_phase11.sh
moon check --target all --warn-list +73
./tools/test_with_count.sh native
./tools/test_with_count.sh wasm
moon run --target native cmd/just -- --version
moon run --target wasm cmd/just -- --version
