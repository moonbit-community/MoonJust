# MoonJust Project Plan

> Status: accepted execution baseline v1.0
>
> Last strict review: 2026-08-25. Phases 0-12 are complete for their declared
> scope. The current closure and release evidence are consolidated in
> [`reports/PHASE_12_REPORT.md`](reports/PHASE_12_REPORT.md) and
> [`reports/RELEASE_AUDIT.md`](reports/RELEASE_AUDIT.md).

## 1. Product and Scope

MoonJust is a MoonBit implementation of the user-visible behavior of
[`just`](https://github.com/casey/just), not a mechanical translation of the
upstream Rust source. The compatibility baseline is `just 1.57.0` at commit
`e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`.

The product targets Native and wasm1 through the MoonBit host runtime. The
stable library facade is `ZSeanYves/MoonJust/api`; `cmd/just` is the executable
entry point. The upstream Rust library API, implementation types, shell
completion generation, browser execution, arbitrary WASI execution, and
wasm-gc process execution are outside the release contract.

The supported Native matrix is Linux x86_64, macOS arm64, and Windows x86_64.
The wasm1 executable is built on Ubuntu, hashed, and consumed by all three
Native platform jobs. The MoonX host limitation for two invalid-UTF-8 cwd cases
is recorded as `not-applicable` evidence.

## 2. Current Baseline

- Module: `ZSeanYves/MoonJust`
- Moon metadata version: `0.1.0`
- Product and release version: `v0.1.0`
- License: Apache-2.0
- Required Moon targets: `native` and `wasm` (`wasm1` under `moonrun`/`moonx`)
- Upstream registration inventory: 2,417 rows
- Completion: explicitly excluded
- Public verification entry point: `python3 tools/runner.py`

All copied or adapted upstream fixtures must be recorded in
[`tests/upstream/NOTICE.md`](../tests/upstream/NOTICE.md) with their upstream
path, commit, license, modification, and compatibility ID. The project name
and release materials must not imply sponsorship or official status from the
upstream project.

## 3. Architecture

The implementation uses pure MoonBit core packages, explicit host capabilities,
and target-specific adapters:

- lexer, parser, AST, semantic analysis, evaluator, dependency graph, and
  execution planning remain independent of host effects;
- filesystem, environment, clock, randomness, terminal, and process behavior
  enter through project-owned capability interfaces;
- Native and wasm1 provide the target adapters;
- `api` exposes only the stable facade and does not leak parser, AST, semantic,
  evaluator, host, or executor implementation types.

The primary wasm environment is MoonBit `moonx`/`moonrun`, not a browser or
arbitrary WASI runtime. Recipe execution requires host-provided filesystem,
environment, and child-process capabilities. Read-only inspection uses
`policies/inspect.toml`; trusted local execution uses the explicitly permissive
`policies/execute.toml`.

Production C is not part of the current architecture. System ABI calls may be
declared through private MoonBit FFI, but the repository has no production C
source or production `native-stub`.

## 4. Compatibility Definition

Compatibility compares six observable surfaces:

| Surface | Compared behavior | Default requirement |
| --- | --- | --- |
| Language | Tokens, AST meaning, settings, attributes, expressions, dependencies, modules | Accept/reject and semantic behavior match. |
| CLI | Arguments, defaults, conflicts, subcommands, cwd, search rules | Behavior and exit status match. |
| Output | stdout/stderr, ordering, newlines, colors, diagnostic locations | Byte equality except for explicit normalizers. |
| Side effects | Files, cwd, environment, and commands started | Operation set, ordering, and failure semantics match. |
| Scheduling | Dependency order, parallel limit, failure propagation, cache hits | Observable behavior matches. |
| Platform | Shell, paths, permissions, signals, terminal, Windows behavior | Match on the same supported target. |

Only explicitly listed normalizers may remove temporary roots, PIDs, wall-clock
values, random IDs, or platform path separators. Broad regular expressions that
hide complete errors, commands, or paths are prohibited.

The official harness classifies results as exact, diagnostic-exact,
diagnostic-semantic, product-identity, excluded-completion, upstream-ignored,
not-applicable, approved-difference, or failed. Unapproved differences fail.
Approved differences require exact test IDs, an owner, a reason, targets, and
machine-readable evidence.

## 5. Process, Signal, and Resource Contract

`moonbitlang/async/process` owns direct-child creation, cancellation, waiting,
reap, pipe resources, and signal status mapping. MoonJust supplies the
cancellation policy and preserves child exit status.

MoonJust does not install a Unix signal handler, create a signal pipe, record raw
signal ordering, or forward TERM itself. Async-owned cancellation maps to a
generic interruption. Signal identity, TERM forwarding, first-signal ordering,
SIGINFO, and signal-specific diagnostics are not product guarantees; ADR-0020
and its async-only evidence record these differences.

Indirect, background, daemon, regrouped, and detached descendants are outside
the lifecycle guarantee. A descendant may hold a shared stdout/stderr pipe
after the direct child has been reaped. Direct-child wait/reap and pipe-reader
EOF are separate observations and must not be conflated.

The host-async package under `spikes/host-async` is historical and isolated. It
is not a production dependency or a current release gate.

## 6. Delivery Phases

The following phase index is historical. Detailed evidence remains in the
corresponding phase report.

| Phase | Scope | Current state |
| --- | --- | --- |
| 0 | Governance, architecture, dependency and CI baseline | Complete |
| 1 | Source/span model, diagnostics, paths, host contracts, application errors | Complete |
| 2 | Target-independent lexer and hardening | Complete |
| 3 | Parser, AST, formatter, and Markdown extraction | Complete |
| 4 | Semantic compilation, loader, imports, and module graph | Complete |
| 5 | Values, evaluator, builtins, effects, and hashing | Complete |
| 6 | Query CLI and read-only wasm inspection | Complete |
| 7 | Host filesystem transactions, dotenv, invocation, cwd, and environment | Complete |
| 8 | Sequential executor, process adapters, scripts, effects, output, and cancellation | Complete |
| 9 | Bounded concurrency, persistent cache, atomic storage, cleanup, and determinism | Complete |
| 10 | Platform behavior, interaction, Markdown, and compatibility convergence | Complete |
| 11 | Packages, policies, artifacts, supply chain, and upgrade rehearsal | Complete |
| 12 | Source layout, C cleanup, async-only signals, documentation, and release closure | Complete for declared scope |

## 7. Verification and CI

The unified Python runner is the public verification interface. It records
commands, exit status, duration, output hashes, platform, toolchain, and
evidence paths. CI and release workflows use Python 3.11 and native path/file
operations on all three platforms. Windows does not require Git Bash.

The normal verification layers are:

```text
python3 tools/runner.py test-tools
python3 tools/runner.py run --mode fast
python3 tools/runner.py run --mode verify
python3 tools/runner.py run --mode compat
python3 tools/runner.py run --mode release
```

PR workflows run fast, verify, contract, compatibility, and three-platform
Native smoke checks. Main pushes and manual releases additionally run coverage,
artifact, and report-only benchmark evidence. Host-async historical probes are
not silently treated as a pass on unsupported platforms.

Coverage merges Native and Wasm raw reports once in release evidence. Only the
merged overall coverage threshold of 80% fails the gate. Changed-line, area,
package-baseline, absolute timing, and baseline-ratio values are reports, not
failure conditions.

Report-only benchmarks run on Linux, macOS, and Windows. They require successful
execution, complete cold/warm samples, valid schema, artifact hashes, exact
commit identity, and toolchain provenance. They do not impose a fixed timing
threshold.

## 8. Release Requirements

The release candidate must provide, from one exact head:

1. Native and Wasm builds with warning-deny all-target checks.
2. Native and Wasm test matrices, architecture, naming, and tools evidence.
3. The pinned 2,417-registration manifest and official non-completion harness.
4. Async-only signal policy evidence and direct-child lifecycle evidence.
5. Linux, macOS, and Windows Native artifacts plus one verified shared wasm1 asset.
6. Artifact size, checksum, repeatability, source package, policy, tamper,
   supply-chain, MoonX asset, and upgrade-rehearsal evidence.
7. Merged overall coverage at or above 80%.
8. Three-platform report-only benchmark provenance and complete samples.
9. Stable API and generated MoonBit interfaces with no unreviewed changes.

The candidate tree must be clean for release artifact generation. Publication,
tag creation, and GitHub Release creation are maintainer-only actions and are
not performed by repository automation.

## 9. Security Boundary

MoonJust executes commands authorized by the user; it does not turn an
untrusted justfile into safe code. `moonrun` policy controls wasm host access,
but an allowed child process may have authority outside that policy. Users and
CI must review justfiles and use an OS or container sandbox for untrusted
commands.

The release review covers shell/argv separation, canonical path authorization,
dotenv and environment redaction, source and resource budgets, cache poisoning,
temporary-file races, process cancellation, dependency provenance, terminal
escaping, and untrusted Markdown resource limits.

## 10. Evidence and Change Control

Architecture decisions that change compatibility, host capabilities, public API,
dependencies, release gates, or security boundaries require an ADR and updated
machine-readable evidence. The current decisions are indexed in
[`adr/README.md`](adr/README.md).

The current release and platform closure is
[`reports/PHASE_12_REPORT.md`](reports/PHASE_12_REPORT.md). The release audit is
[`reports/RELEASE_AUDIT.md`](reports/RELEASE_AUDIT.md). Historical phase reports
are retained for traceability and must not be used to override the current
Phase 12 contract.
