# MoonJust

MoonJust is a MoonBit implementation of the
[`just`](https://github.com/casey/just) command runner. The project targets
behavioral compatibility with `just 1.57.0` on MoonBit's Native and wasm1
backends.

> Status: Phase 0-7 exits have passed. The Phase 7 pre-execution filesystem,
> environment, invocation, and working-directory models have passed remote CI
> plus a strict second review. Recipe execution remains a Phase 8 capability.

## Compatibility scope

- Compatibility baseline: `just 1.57.0`
  (`e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`).
- Required backends: `native` and `wasm` under `moonx`/`moonrun`.
- The pure library core will remain independent of host I/O capabilities.
- Shell completion generation is intentionally out of scope.
- The Wasm execution target is the MoonBit host runtime, not browsers or
  arbitrary WASI runtimes.

The complete scope, architecture, PR sequence, quality gates, and release
criteria are defined in [the project plan](docs/PROJECT_PLAN.md). The current
Phase 0-5 verdict and resolved exit evidence are recorded in the
[strict audit](docs/PHASE_0_5_AUDIT.md), with implementation evidence in the
[Phase 5 report](docs/PHASE_5_REPORT.md), [Phase 4 report](docs/PHASE_4_REPORT.md),
[Phase 3 report](docs/PHASE_3_REPORT.md), [Phase 2 report](docs/PHASE_2_REPORT.md),
[Phase 1 report](docs/PHASE_1_REPORT.md),
[Phase 6 report](docs/PHASE_6_REPORT.md), and the
[Phase 7 report](docs/PHASE_7_REPORT.md).

## Development

The current toolchain baseline is:

```text
moon 0.1.20260803
moonc 0.10.6+62c2592d1
moonrun 0.1.20260803
```

Run the local quality gate:

```bash
./tools/check.sh
```

Run the executable smoke test directly:

```bash
moon run --target native cmd/just -- --version
moon run --target wasm cmd/just -- --version
./tools/check_phase6_inspect.sh
```

The pre-commit hook can be enabled with:

```bash
git config core.hooksPath .githooks
```

## Security

A justfile can execute arbitrary commands. MoonJust does not make an untrusted
justfile safe merely by running it through Wasm. See [SECURITY.md](SECURITY.md)
before executing unreviewed recipes.

## License

MoonJust is licensed under Apache-2.0. The upstream `just` project is licensed
under CC0-1.0; copied or adapted compatibility fixtures retain explicit
provenance under `tests/upstream/`.
