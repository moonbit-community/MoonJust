# Tooling

`tools/check.sh` is the complete local quality entry point. CI also invokes
individual gates from `checks/` so failures remain attributable to one area.

| Directory | Responsibility |
| --- | --- |
| `checks/` | architecture, compatibility, execution, platform, release, and target gates |
| `differential/` | reusable Native/Wasm differential runner and self-tests |
| `oracles/` | external reference implementations used by compatibility gates |
| `probes/` | internal MoonBit executables used to expose typed behavior to gates |
| `release/` | artifact construction, verification, supply chain, and rollback tooling |
| `spikes/` | retained ecosystem and host capability qualification checks |
| `upstream/` | pinned `just` inventory, oracle, manifest, and harness tooling |

Keep specialized gates separate instead of growing `check.sh` into a single
opaque script. Generated build output and language caches belong under ignored
cache directories, never in this tree.
