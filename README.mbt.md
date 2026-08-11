# MoonJust

MoonJust is a MoonBit implementation of the user-visible behavior of
[`just`](https://github.com/casey/just), targeting Native and wasm1 through the
MoonBit host runtime. The compatibility baseline is pinned to `just 1.57.0`;
the upstream Rust library API is not part of MoonJust's public API.

> **Current status**
>
> Phase 0-8 exits have passed. Phase 9 implementation and local gates are
> complete; its final exit awaits protected remote CI. MoonJust `0.6.0-alpha`
> adds bounded parallel scheduling and a versioned Native/wasm1 recipe cache.

## What is delivered

The completed phases establish a usable and auditable foundation:

| Area | Current capability |
| --- | --- |
| Language core | UTF-8 byte spans, diagnostics, lexer, parser, AST, formatter, semantic compilation |
| Loading | justfile discovery, explicit paths, stdin, imports, optional imports, modules and canonical graph identity |
| Evaluation | lazy scopes, recipe parameters, typed values, 83 builtins, explicit host effects, bounded hashing |
| Query CLI | check, format, init, list, show, summary, usage, groups, variables, evaluate, dump and JSON inspection |
| Filesystem | Native atomic transactions and policy-aware wasm1 transaction adapter |
| Environment | dotenv parsing/discovery, required/list/command modes, overrides, shell/tempdir and child-environment composition |
| Invocation | positional/variadic parameters, recipe-local options, flags, repetition, patterns and stable usage errors |
| Working directory | invocation, project, module, evaluation and recipe directory model with `no-cd` and recipe overrides |
| Executor | bounded jobs, parallel/serial dependency fences, scripts, cache, dry-run, deterministic output/failure and cancellation cleanup |
| Wasm boundary | separate read-only inspect and process-enabled execution policies |

The CLI validates the complete recipe graph before execution, then runs ready
tasks through a bounded FIFO scheduler. Cache entries are BLAKE3-keyed,
versioned, locked across processes and atomically published after output checks.

## Compatibility and support

- Upstream: `just 1.57.0`, commit
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`.
- Required targets: `native` and `wasm` (`wasm1` under `moonrun`/`moonx`).
- Validated upstream registrations: 1,597 executable rows across Phases 2-7 and 9.
- Explicitly excluded or not applicable: shell completion, Rust-internal tests,
  and product-maintenance commands.
- Deferred: 784 upstream registrations owned by the remaining full-executor and
  Phase 10 interactive/release compatibility work.
- Browser, arbitrary WASI, wasm-gc process execution and child-process
  sandboxing are not supported claims.

The complete decision record is in the
[Phase 0-9 strict audit](docs/PHASE_0_9_AUDIT.md). Machine-readable scope and
phase contracts live under [`compat/`](compat/); the pinned corpus provenance
is in [`tests/upstream/NOTICE.md`](tests/upstream/NOTICE.md).

## Quick start

### Prerequisites

The repository currently uses:

```text
moon 0.1.20260803
moonc 0.10.6+62c2592d1
moonrun 0.1.20260803
```

Install the matching MoonBit toolchain, then enable the repository hook:

```bash
git config core.hooksPath .githooks
```

### Build and inspect

```bash
moon check --target all --warn-list +73
moon build --target native cmd/just
moon build --target wasm cmd/just
moon run --target native cmd/just -- --help
moon run --target native cmd/just -- --version
```

The Wasm executable requires an explicit MoonBit host policy. The published
inspection policy is intentionally read-only:

```bash
moonrun --policy policies/inspect.toml \
  _build/wasm/debug/build/cmd/just/just.wasm --help
```

### Run the release gate

```bash
./tools/check.sh
```

The gate checks architecture boundaries, pinned upstream metadata, the
differential harness, all stable backends, Wasm policy, five Phase 7
differentials, public interfaces, and the complete Native/wasm1 test matrix.

## Architecture

MoonJust keeps behavior-bearing logic in pure or capability-parameterized
packages and isolates platform details at adapter leaves:

```text
argv / stdin / cwd / explicit host facts
        |
        v
CLI composition and validation
        |
        v
loader -> source -> lexer -> parser -> semantic model
                                  |
                                  v
                    evaluator / invocation / query
                                  |
                                  v
              working directory + environment configuration
                                  |
                                  v
                    Phase 8 executor boundary
```

The core never reads process-global environment or filesystem state directly.
`HostFs`, `HostEnv`, `HostClock`, `HostRandom`, `HostProcess`, `HostTerminal`,
`HostSignal` and `HostPlatform` make those inputs explicit and testable. The
Wasm inspection adapter receives only the capabilities its policy allows.

## Repository map

| Path | Responsibility |
| --- | --- |
| `src/source`, `src/diagnostic`, `src/path` | target-independent source coordinates, diagnostics and lexical paths |
| `src/lexer`, `src/parser`, `src/syntax`, `src/formatter` | language front end and Markdown tangle |
| `src/semantic`, `src/loader`, `src/evaluator`, `src/builtin` | compilation, graph loading, evaluation and typed builtins |
| `src/host`, `src/host_native`, `src/host_wasm` | explicit host contracts and platform adapters |
| `src/cli`, `src/application`, `src/invocation`, `src/workdir`, `src/environment` | CLI composition and Phase 6-7 models |
| `cmd/just` | Native/wasm1 executable composition root |
| `compat/` | machine-readable compatibility inventories and phase contracts |
| `tests/upstream/` | pinned upstream corpus, ownership map and provenance |
| `tools/` | deterministic gates, oracle builders and differential probes |
| `docs/` | plan, ADRs, phase reports and strict audit |

## Security boundary

A justfile is executable code. Passing through Wasm does not automatically
sandbox a spawned child process, and granting a `moonrun` process policy does
not make an untrusted recipe safe. Review untrusted justfiles and use an
operating-system or container sandbox when isolation is required. Report
potential command injection, path escape, secret disclosure, cache poisoning
or process-isolation vulnerabilities privately as described in
[SECURITY.md](SECURITY.md).

Environment and override containers deliberately avoid `Debug` derivations.
Diagnostics redact dotenv values, command arguments, child stderr and host
environment entries. Atomic writes use same-directory temporary files, mode
`0600`, synchronization before commit and typed cleanup failures.

## Development workflow

Every behavior change must identify its compatibility tier, upstream reference,
supported targets, and regression evidence. Use the existing package boundaries
and ADRs before introducing a new abstraction.

```bash
moon check --target all --warn-list +73
moon test --target native
moon test --target wasm
moon info
moon fmt
./tools/check.sh
```

Before opening a PR, review generated `.mbti` diffs, run the applicable
differential gate, and confirm that unsupported behavior is rejected explicitly
instead of silently ignored. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
definition of ready and required PR evidence.

## Documentation index

- [Project plan](docs/PROJECT_PLAN.md): scope, architecture, compatibility tiers and future phases.
- [Phase 0-9 strict audit](docs/PHASE_0_9_AUDIT.md): current cross-phase verdict and publication evidence.
- [Phase 0 report](docs/PHASE_0_REPORT.md) through [Phase 7 report](docs/PHASE_7_REPORT.md): phase-local delivery records.
- [Architecture](docs/ARCHITECTURE.md): package boundaries and capability flow.
- [ADR index](docs/adr/README.md): accepted design decisions.
- [Security policy](SECURITY.md): threat model and disclosure boundary.
- [Changelog](CHANGELOG.md): user-visible project history.

## License and provenance

MoonJust is licensed under Apache-2.0. The pinned upstream `just` fixtures are
CC0-1.0 and retain their source, commit, license and modification provenance in
[`tests/upstream/NOTICE.md`](tests/upstream/NOTICE.md). MoonJust is an
independent project and is not sponsored or endorsed by the upstream authors.
