# Changelog

All notable changes to MoonJust will be documented here. The project follows
[Semantic Versioning](https://semver.org/) independently of upstream `just`.

## Unreleased

### Added

- Phase 8 shell-independent process IR with explicit environment and stdio
  policies, signal-aware results, deterministic fake-host assertions, and
  redacted structural diagnostics.
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
