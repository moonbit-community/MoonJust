# Changelog

All notable changes to MoonJust will be documented here. The project follows
[Semantic Versioning](https://semver.org/) independently of upstream `just`.

## Unreleased

### Added

- Phase 9 bounded FIFO recipe scheduling with `--jobs`, parallel dependency
  groups, serial fences, deterministic output, and stable failure selection.
- Phase 9 versioned BLAKE3 cache keys, strict manifests, Native/wasm1
  per-digest locks, atomic publication, selective clean, corruption recovery,
  crash recovery, and cross-process contention handling.
- Phase 9 resource hardening with incremental input hashing, concurrently
  drained process pipes, a 16 MiB per-stream capture budget, and locked stale
  cache-temporary cleanup.
- Phase 8 shell-independent process IR with explicit environment and stdio
  policies, signal-aware results, deterministic fake-host assertions, and
  redacted structural diagnostics.
- Phase 8 ordinary recipe-line execution with interpolation, exact shell argv,
  echo and quiet behavior, ignored failures, and side-effect-free dry runs.
- Phase 8 script/shebang execution, effectful backticks and `shell()`, ordered
  dependencies, retained failure output, cancellation-safe cleanup, and a
  policy-controlled wasm1 process adapter.
- Phase 0 repository foundation for Native and wasm1 development.
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
- Machine-checked Phase 1 architecture and compatibility manifests.
