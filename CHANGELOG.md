# Changelog

This file records user-visible changes recovered from the repository's commit
and pull-request history. MoonJust follows Semantic Versioning independently of
the upstream just version it implements.

The repository has not created Git tags or GitHub Releases yet. Dates below are
the dates on which the corresponding moon.mod version entered source history;
early 0.3.0 through 0.7.0-alpha.1 entries were development snapshots, not
published releases.

## Unreleased - 0.1.2 development line

### Changed

- Rebuilt MoonJust as a binary-only module with the executable in the root
  package. moon run . replaces the former cmd/just path.
- Removed the public api facade and moved all implementation packages under
  internal/; this intentionally breaks the former MoonBit library surface but
  does not change the just-compatible executable contract.
- Established explicit application, project, query, planner, runtime, and Host
  ownership around one forward-only execution chain.
- Grouped Host contracts and the fs, native, process, testkit, and wasm
  adapters below internal/host/.
- Replaced the old executor/scheduler split with planning-owned graph and
  schedule models plus runtime-owned process coordination.
- Replaced custom release, architecture-count, contract-count, Python, Rust,
  shell, C, and spike tooling with focused MoonBit behavior, compatibility,
  platform, and benchmark runners.
- Moved historical ADRs and delivery reports to docs/development/; current
  architecture and maintenance records now have separate locations.
- Made `moon.mod` version 0.1.2 authoritative for the executable identity and
  added a preflight check that rejects a mismatched `--version` response.
- Expanded compatibility evidence to emit a per-identity report for all 2,417
  pinned upstream test names, with explicit completion/signal exclusions and
  visible unclassified coverage.
- Reworked the benchmark runner around larger workloads, warmups, interleaved
  batches, ratio intervals and JSON gate artifacts for Native and Wasm. Wasm
  runner arguments now use the required `moonrun ... -- ...` form.

### Performance

- Reused invocation Host snapshots and fused redundant Wasm source reads.
- Kept project loading and single-root semantic compilation on cached,
  allocation-conscious paths.
- Added safe synchronous paths for static CLI, summary, format, check, recipe
  parsing, unchanged formatting, and empty dry-run requests.
- Avoided dry-run execution-host/task materialization and retained optimized
  empty DAG planning.
- Reduced Windows drive-path conversion and repeated process-resolution work.
- Added runtime-floor and paired benchmark evidence while preserving the
  regular Moon build/publish path.

### Fixed

- Preserved loader candidate error precedence, project dependency diagnostics,
  source-size limits, and async signal compatibility while optimizing.
- Made candidate executable paths stable after compatibility runners enter an
  isolated case directory.
- Made platform differential output exact and independent of per-process
  temporary working-directory names.
- Pinned every accepted diagnostic difference to exact candidate bytes with a
  pure MoonBit SHA-256 implementation.

### Verification

- The current corpus reports 176 exact matches, 6 pinned known differences,
  and 0 failures against official just 1.57.0.
- Native/Wasm rewrite comparisons against the performance baseline have median
  1.00x; artifact growth remains below one percent on both targets.
- PR #69 passed Ubuntu, macOS, Windows, Wasm, formatting/interface, and official
  differential CI before merge.

## 0.1.1 - 2026-08-25

### Changed

- Prepared the ZSeanYves/MoonJust Mooncakes package at version 0.1.1 and
  refreshed the English release documentation.
- Adopted the latest compatible MoonBit dependency set and made registry update
  handling more resilient.
- Removed MoonJust-owned signal forwarding in favor of direct-child lifecycle
  behavior and explicit async-only compatibility evidence.
- Consolidated CI orchestration and separated platform, official differential,
  and release-evidence checks.

### Fixed

- Waited for direct child completion while draining stdout/stderr concurrently.
- Preserved the documented signal-forwarding limitation rather than masking it
  with private process-group behavior.

## 0.1.0 - 2026-08-24

### Added

- Completed the just 1.57 command surface across parsing, formatting, semantic
  validation, project loading, evaluation, queries, recipe execution,
  concurrency, caching, environment composition, working directories, terminal
  interaction, and Native/Wasm Host adapters.
- Added Linux, macOS, Windows, and Wasm compatibility evidence plus package,
  artifact, dependency, provenance, repeatability, and upgrade checks.

### Changed

- Renamed the module from moonbit-community/MoonJust to ZSeanYves/MoonJust and
  reset development metadata from 0.7.0-alpha.1 to the first intended package
  version, 0.1.0.
- Returned implementation packages to src/ for the Phase 12 layout, removed
  project-owned production C shims, and retained platform behavior in MoonBit.
- Classified the full historical 2,417-row upstream inventory and documented
  completion, host, and signal boundaries explicitly.

## Development Metadata History

These versions appeared in moon.mod while the implementation was being built.
They were never represented by repository tags or GitHub Releases.

### 0.7.0-alpha.1 - 2026-08-13

- Added source-package, cross-platform artifact, checksum, SBOM, provenance,
  tamper-resistance, and upgrade/rollback engineering.
- Marked the release-engineering snapshot as pre-release metadata.

### 0.7.0 - 2026-08-13

- Added platform and terminal facts, interactive flows, Markdown extraction,
  and broad Tier B compatibility convergence work.
- Completed the then-current upstream registration classification and platform
  matrix.

### 0.6.0 - 2026-08-11

- Added bounded scheduling, parallel and subsequent dependencies, deterministic
  failure selection, persistent cache keys, leases, atomic publication,
  corruption recovery, and cross-process contention handling.

### 0.5.0 - 2026-08-10

- Added the sequential recipe executor, process adapters, ordinary and script
  recipes, dry-run behavior, output capture, effectful evaluation, and
  cancellation cleanup.

### 0.3.0 - 2026-08-07

- Added the composed Native/Wasm query CLI: check, format, init, list, show,
  summary, usage, evaluate, dump, and JSON inspection.
- Added atomic Host filesystem operations, dotenv, invocation parsing, working
  directory modeling, and environment composition during the following Phase 7
  work on this metadata line.

### 0.1.0 - 2026-08-04

- Established the repository, pinned official just 1.57.0 at commit
  e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f, and created the initial
  differential inventory.
- Added source/span, diagnostics, lexical paths, Host contracts, the lexer,
  parser, syntax tree, formatter, Markdown tangle, semantic compiler, loader,
  evaluator, builtins, and the first Native/Wasm adapters.

[Unreleased]: https://github.com/moonbit-community/MoonJust/compare/8ae279fe...HEAD
[0.1.1]: https://github.com/moonbit-community/MoonJust/commit/8ae279fef0e3f445b19c57c24f34aa921165f1cb
[0.1.0]: https://github.com/moonbit-community/MoonJust/commit/354869e00f88af167ce5fdb0a38a1f6687c71122
