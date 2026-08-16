# MoonJust

MoonJust is a MoonBit implementation of the user-visible behavior of
[`just`](https://github.com/casey/just), targeting Native and wasm1 through the
MoonBit host runtime. The compatibility baseline is pinned to `just 1.57.0`;
the upstream Rust library API is not part of MoonJust's public API.

> **Current status**
>
> MoonJust is compatible with the pinned `just 1.57.0` Tier A surface on
> native and wasm/moonrun. Completion, browser execution and arbitrary WASI
> remain outside scope. No publication, tag or GitHub Release is performed by
> the compatibility gate.

## What is delivered

The current release surface is usable and auditable:

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
| Platform and terminal | real Native OS/architecture/TTY facts, signal-aware statuses, deterministic color and Unicode display width |
| Interactive and Markdown | confirm/yes, chooser/editor workflows and automatic source-aware Markdown extraction |
| Wasm boundary | separate read-only inspect and process-enabled execution policies |
| Release engineering | validated Mooncakes source package, MoonX staging, cross-platform candidates, checksums, SBOM/provenance and upgrade rollback |

The CLI validates the complete recipe graph before execution, then runs ready
tasks through a bounded FIFO scheduler. Cache entries are BLAKE3-keyed,
versioned, locked across processes and atomically published after output checks.

## Compatibility and support

- Upstream: `just 1.57.0`, commit
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`.
- Required targets: `native` and `wasm` (`wasm1` under `moonrun`/`moonx`).
- Tier A registrations: 2,328 total; 1,758 verified by official/native/wasm
  differential execution, 569 by executable contract cases, one explicitly
  not applicable, and zero unsupported or unverified.
- Full pinned inventory: 2,366 verified, five Tier B chooser/submodule/SIGINFO
  differences, 35 excluded completion rows and eleven not-applicable
  Rust-internal, testing-interface or product-maintenance rows.
- Structured CLI differential corpus: 147 exact matches and 35 bounded
  product-identity or diagnostic-layout differences, with zero failures.
- Browser, arbitrary WASI, wasm-gc process execution and child-process
  sandboxing are not supported claims.

The complete decision record is in the
[release readiness audit](docs/reports/RELEASE_AUDIT.md). Machine-readable scope and
area contracts live under [`compat/`](compat/); the pinned corpus provenance
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
differential harness, all stable backends, Wasm policies, execution-context
differentials, executor and runtime behavior, release readiness, the pinned
Markdown oracle, public interfaces, and the complete Native/wasm1 test matrix.

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
                    platform-aware executor boundary
```

The core never reads process-global environment or filesystem state directly.
`HostFs`, `HostEnv`, `HostClock`, `HostRandom`, `HostProcess`, `HostTerminal`,
`HostSignal` and `HostPlatform` make those inputs explicit and testable. The
Wasm inspection adapter receives only the capabilities its policy allows.

## Repository map

| Path | Responsibility |
| --- | --- |
| `api/` | stable public library facade and build metadata |
| `src/source`, `src/diagnostic`, `src/path` | target-independent source coordinates, diagnostics and lexical paths |
| `src/lexer`, `src/parser`, `src/syntax`, `src/formatter` | language front end and Markdown tangle |
| `src/semantic`, `src/loader`, `src/evaluator`, `src/builtin` | compilation, graph loading, evaluation and typed builtins |
| `src/host`, `src/host_native`, `src/host_wasm` | explicit host contracts and platform adapters |
| `src/cli`, `src/application`, `src/invocation`, `src/workdir`, `src/environment` | CLI, invocation, working-directory and environment models |
| `cmd/just` | Native/wasm1 executable composition root |
| `compat/` | machine-readable compatibility inventories and area contracts |
| `tests/upstream/` | pinned upstream corpus, ownership map and provenance |
| `tools/` | deterministic gates, oracle builders and differential probes |
| `docs/` | design plan, ADRs, historical delivery reports and release audit |

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
environment entries. Atomic writes use one reserved same-directory temporary
name per digest, mode `0600`, synchronization before commit and typed cleanup
failures. The next matching lease and full cache clean remove that name only
while holding the digest lock; lookalike files are preserved. Child stdout and
stderr are drained concurrently;
retained streams have a 16 MiB per-stream limit, and overflow cancels the
child with a deterministic error.

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

- [Project plan](docs/PROJECT_PLAN.md): scope, architecture, compatibility tiers and historical delivery sequence.
- [Release readiness audit](docs/reports/RELEASE_AUDIT.md): current consolidated verdict, remediation and remote evidence.
- [Historical delivery reports](docs/reports/README.md): milestone-local records retained for traceability.
- [Public API](docs/API.md) and [release policy](docs/RELEASE_POLICY.md): package surface, candidate integrity and maintainer-only publication boundary.
- [Architecture](docs/ARCHITECTURE.md): package boundaries and capability flow.
- [ADR index](docs/adr/README.md): accepted design decisions.
- [Security policy](SECURITY.md): threat model and disclosure boundary.
- [Changelog](CHANGELOG.md): user-visible project history.

## License and provenance

MoonJust is licensed under Apache-2.0. The pinned upstream `just` fixtures are
CC0-1.0 and retain their source, commit, license and modification provenance in
[`tests/upstream/NOTICE.md`](tests/upstream/NOTICE.md). MoonJust is an
independent project and is not sponsored or endorsed by the upstream authors.
