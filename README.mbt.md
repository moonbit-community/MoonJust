# MoonJust

MoonJust is a MoonBit implementation of the
[`just`](https://github.com/casey/just) command runner. The project targets
behavioral compatibility with `just 1.57.0` on MoonBit's Native and wasm1
backends.

> Status: Phase 4 semantic compilation and host-backed loading complete. Pure
> value evaluation and execution are still under development.

## Compatibility scope

- Compatibility baseline: `just 1.57.0`
  (`e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`).
- Required backends: `native` and `wasm` under `moonx`/`moonrun`.
- The pure library core will remain independent of host I/O capabilities.
- Shell completion generation is intentionally out of scope.
- The Wasm execution target is the MoonBit host runtime, not browsers or
  arbitrary WASI runtimes.

The complete scope, architecture, PR sequence, quality gates, and release
criteria are defined in [the project plan](docs/PROJECT_PLAN.md). Phase 2 exit
evidence and known limitations are recorded in
[the Phase 4 completion report](docs/PHASE_4_REPORT.md), the
[Phase 3 report](docs/PHASE_3_REPORT.md), and the
[Phase 1 report](docs/PHASE_1_REPORT.md) remains available for provenance.

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
