# Tooling

`python3 tools/runner.py` is the only public verification entry point. The
runner records one evidence document per invocation and keeps individual probes
under `tools/verification/` so failures remain attributable to one area.

| Directory | Responsibility |
| --- | --- |
| `verification/` | runner, registry, evidence schema, checks, and benchmark probes |
| `differential/` | reusable Native/Wasm differential runner and self-tests |
| `oracles/` | external reference implementations used by compatibility gates |
| `probes/` | internal MoonBit executables used to expose typed behavior to gates |
| `quality/` | coverage collection, aggregation, and quality evidence |
| `release/` | artifact construction, verification, supply chain, and rollback tooling |
| `spikes/` | retained host capability qualification checks |
| `upstream/` | pinned `just` inventory, oracle, manifest, and harness tooling |
Generated build output and language caches belong under ignored cache
directories, never in this tree.

Coverage is collected through `tools/quality/collect_coverage.py`, once per
target. It isolates trace files under `_build/coverage/<target>/`, records
source and trace hashes with the resolved MoonBit toolchain, and rejects stale
traces before producing Cobertura output.
