# Tooling

`tools/check.sh` is the local correctness entry point. CI also invokes
individual gates from `checks/` so failures remain attributable to one area.
The release-only gate is opt-in with `tools/check.sh --release`; release CI
always invokes it explicitly.

| Directory | Responsibility |
| --- | --- |
| `checks/` | architecture, compatibility, execution, platform, release, and target gates |
| `differential/` | reusable Native/Wasm differential runner and self-tests |
| `oracles/` | external reference implementations used by compatibility gates |
| `probes/` | internal MoonBit executables used to expose typed behavior to gates |
| `quality/` | coverage collection, aggregation, and quality evidence |
| `release/` | artifact construction, verification, supply chain, and rollback tooling |
| `spikes/` | retained ecosystem and host capability qualification checks |
| `upstream/` | pinned `just` inventory, oracle, manifest, and harness tooling |

Keep specialized gates separate instead of growing `check.sh` into a single
opaque script. Generated build output and language caches belong under ignored
cache directories, never in this tree.

Coverage is collected through `tools/quality/collect_coverage.py`, once per
target. It isolates trace files under `_build/coverage/<target>/`, records
source and trace hashes with the resolved MoonBit toolchain, and rejects stale
traces before producing Cobertura output.
