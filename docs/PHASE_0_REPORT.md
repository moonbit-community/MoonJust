# Phase 0 completion report

- Status: Complete
- Review date: 2026-08-04
- Upstream baseline: `just 1.57.0`
- Required implementation targets: Native and wasm1
- Decision: Proceed to Phase 1 (`Source`, diagnostics, platform value model)

## Scope statement

Phase 0 established the repository, compatibility baseline, architecture,
quality gates, and dependency evidence needed to begin implementation. It did
not implement justfile parsing or recipe execution. MoonJust remains an
`0.1.0-alpha.0` foundation and must not yet be presented as a replacement for
`just`.

The 2026-08-06 re-certification adds a deterministic JSONL row for every
upstream registration, a fixed-source `just 1.57.0` Cargo oracle builder, and
structured TOML/outline validation. The historical Phase 0 decision remains
valid only for the pinned research baseline; these scripts are the evidence
used by all subsequent phase exits.

## Work units

The repository was empty when work began, so Phase 0 bootstrap units were
delivered as small, independently checked commits. Protected-main pull requests
are required after the bootstrap sequence.

| Plan unit | Commit | Delivered evidence |
| --- | --- | --- |
| PR-000/001 | `d2af932` | Repository hygiene, module/CLI identity, governance files, shared local gate, hooks, Native/wasm1 smoke, Linux/macOS/Windows CI |
| PR-002 | `932fe71` | Architecture and ADR-0001 through ADR-0005 |
| PR-003 | `af94e38` | Exact `just 1.57.0` manifest, generated 2,417-test inventory, CLI/builtin/setting/attribute snapshots, provenance verifier |
| PR-004 | `5a33c45` | Isolated differential runner, strict normalizer, artifacts, expected-difference registry, self-test, ten bootstrap cases |
| PR-005 | `72854f1` | Exact `moonbitlang/async 0.20.3` spike and Native/wasm1 filesystem/process/cancellation report |
| PR-006 | `ac0a5ce` | UTF-8 span, cmark, regexp, and time contracts; dependency/license/size decisions; Native/wasm1 benchmarks; ADR-0007/0009 |
| Solo governance | `52fd875` | Removed staffing/schedule assumptions and replaced multi-review requirements with independent-maintainer self-review gates |
| CI remediation | `db5154a` | Fresh-run registry synchronization for isolated nested modules |

## Exit evidence

| Exit | Evidence | Result |
| --- | --- | --- |
| Clean, independent repository | Own `.git`, `origin` at `moonbit-community/MoonJust`, generated template debris removed | Pass |
| Product identity | Module `moonbit-community/MoonJust`; executable package `cmd/just`; upstream baseline reported by `--version` | Pass |
| Cross-target build | `moon check --target all --warn-list +73` | Pass |
| Native and wasm1 smoke | Root tests select 2/2 per target at the final audit; CLI version smoke on both targets | Pass |
| Platform smoke | GitHub-hosted Linux, macOS, and Windows Native jobs | Pass |
| Public API stability check | `moon info` followed by a clean diff in CI | Pass |
| Upstream provenance | Exact tag, commit, release metadata, test-list hash, and CC0 fixture notice | Pass |
| Differential infrastructure | Self-test has one exact match and one registered XDIFF; real bootstrap run records ten expected incompatibilities with raw artifacts | Pass |
| Host dependency decision | Four contract tests on Native and wasm1, covering file I/O, cwd/env, stdout/stderr/exit, stdin, and hard cancellation | Pass |
| Ecosystem dependency decision | Ten contract tests on Native and wasm1; four reproducible microbenchmarks per target | Pass |
| Warnings and script quality | No new MoonBit warnings; shell scripts pass `shellcheck`; `git diff --check` clean | Pass |
| Remote CI | Run `30905830657`: quality plus all three Native platform jobs succeeded | Pass |
| Main governance | Strict required checks, linear history, admin enforcement, no force-push/delete, no approval-count requirement | Pass |

The inspected main runs did not reveal an intermittent test failure. Two runs
failed deterministically because a fresh runner's registry index did not yet
contain nested spike dependencies. Commit `db5154a` adds an explicit update
step; the subsequent clean run passed every job. This is recorded rather than
discarded as noise.

## Frozen decisions

- Product name is MoonJust; the compatibility executable is `just` from
  `cmd/just`.
- The first compatibility baseline is exact `just 1.57.0` commit
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`.
- Source and AST spans use validated UTF-8 bytes, not MoonBit string indexes.
- Core logic is pure; filesystem, environment, process, clock, random,
  terminal, signal, and platform behavior enter through project-owned Host
  contracts.
- wasm1 means `moonx`/`moonrun` with explicit policy. Browser and arbitrary
  WASI execution are not first-release claims.
- `moonbitlang/async 0.20.3`, `cmark 0.4.4`, `regexp 0.3.5`, and `x/time 0.4.47`
  remain private, exact-version candidates behind adapters and later corpus
  gates. They are not root production dependencies.
- Rust-compatible regexp replacement and datetime formatting remain
  project-owned behavior because current package APIs do not match the required
  contracts.
- Shell completion remains excluded.

## Known limitations and assigned gates

- The current CLI only reports version information. All ten real differential
  bootstrap cases are registered expected differences until implementation
  reaches them.
- Windows HostProcess details, TTY behavior, graceful signals, process groups,
  large-output backpressure, locking, and published policy profiles are not
  proven by the Phase 0 async spike.
- The cmark result proves block selection and source-location availability, not
  complete byte-for-byte tangle output. PR-036 and PR-104 own the full gate.
- The regexp engine differs from Rust syntax and accepts unsafe supersets such
  as backreferences. PR-053 must validate/translate syntax, reject supersets,
  implement replacement semantics, and pass a Rust oracle.
- Local time-zone discovery, DST behavior, and chrono-format compatibility are
  deferred to the time adapter and builtin phases.
- At the original Phase 0 entry, the compatibility inventory was only indexed.
  The final Phase 0-5 audit now classifies Phase 2-5 rows as `covered-by` or
  `not-applicable`, with later Phase 6-10 rows remaining explicitly `planned`.
  Future classification remains a 1.0 gate.

No open item above blocks Phase 1. Each blocks the later feature or release tier
named in the project plan and cannot be silently treated as supported.

## Phase 1 entry

Begin with PR-010 through PR-014 in order:

1. UTF-8 `Source`, `SourceId`, byte `Span`, and line index.
2. Target-independent diagnostic IR and text renderer.
3. Unix/Windows-flavored path value model.
4. Host contracts and deterministic fake host.
5. Application error and exit-status mapping.

Do not start the lexer until the Source/Span and diagnostic invariants pass on
Native and wasm1. Do not add the isolated spike dependencies to the root module
without their designated adapter PR and compatibility evidence.
