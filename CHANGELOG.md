# Changelog

All notable changes to MoonJust will be documented here. The project follows
[Semantic Versioning](https://semver.org/) independently of upstream `just`.

## Unreleased

### Added

- Release-candidate engineering for Linux x86_64, macOS x86_64 and
  aarch64, Windows x86_64, and linear-memory wasm1 artifacts.
- Deterministic archives, SHA-256 manifests, CycloneDX 1.5 SBOMs,
  SLSA-compatible provenance, GitHub OIDC candidate attestations, exact
  dependency/license audit, and twelve-class tamper rejection.
- Mooncakes metadata and safe source-package validation, executable public API
  documentation, and local MoonX registry staging with cold-cache checksum
  validation.
- Deny/default-deny, read-only inspect, controlled CI, and explicit execute
  policies with real wasm smoke tests and documented capability boundaries.
- Cache-disabled source-package rebuilds, fixed-path repeatability checks, and
  previous-to-current query/execution upgrade plus byte-exact rollback rehearsal.
- Native platform/architecture/TTY facts, signal-aware execution,
  confirmation, chooser/editor workflows, deterministic terminal rendering,
  source-aware Markdown extraction, and complete compatibility accounting.
- Bounded FIFO recipe scheduling with `--jobs`, parallel dependency
  groups, serial fences, deterministic output, and stable failure selection.
- Versioned BLAKE3 cache keys, strict manifests, Native/wasm1
  per-digest locks, atomic publication, selective clean, corruption recovery,
  crash recovery, and cross-process contention handling.
- Resource hardening with incremental input hashing, concurrently
  drained process pipes, a 16 MiB per-stream capture budget, and locked stale
  cache-temporary cleanup.
- Shell-independent process IR with explicit environment and stdio
  policies, signal-aware results, deterministic fake-host assertions, and
  redacted structural diagnostics.
- Ordinary recipe-line execution with interpolation, exact shell argv,
  echo and quiet behavior, ignored failures, and side-effect-free dry runs.
- Script/shebang execution, effectful backticks and `shell()`, ordered
  dependencies, retained failure output, cancellation-safe cleanup, and a
  policy-controlled wasm1 process adapter.
- Repository foundation for Native and wasm1 development.
- Compatibility planning baseline for `just 1.57.0`.
- Reproducible upstream inventory and differential harness.
- Isolated Native/wasm1 qualification for async host and parser ecosystem
  candidates.
- Independent-maintainer governance, required CI, and protected `main`.
- Validated UTF-8 source storage, byte spans, line indexing, and source maps.
- Structured, ANSI-free diagnostic IR and deterministic plain-text rendering.
- Host-independent Unix and Windows lexical path values.
- Project-owned Host capability traits and a deterministic in-memory FakeHost.
- Typed application requests, failure stages, binary responses, and
  upstream-compatible exit-status mapping.
- Machine-checked architecture and compatibility manifests.

### Fixed

- Redacted script bodies, arguments, `extra`, and environment values from
  verbose cache-key diagnostics.
- Replaced quadratic readiness rescans with an incremental stable scheduler
  queue for large dependency graphs.
