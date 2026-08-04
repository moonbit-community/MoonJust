# ADR-0006: Public API and semantic versioning

- Status: Accepted
- Date: 2026-08-04

## Context

MoonJust needs reusable parse, check, format, query, planning, and execution
interfaces in addition to its command-line executable. Copying upstream Rust
types would expose implementation details and lifetimes that do not form part
of `just` compatibility. MoonBit package interfaces are also visible before the
eventual root facade is introduced.

## Decision

- The root package will own the stable user-facing facade. Internal packages
  expose only the types required for composition and black-box testing.
- Public structures keep fields private. Mutable collections are returned as
  `ArrayView`, `ReadOnlyArray`, or immutable byte views rather than writable
  implementation storage.
- Third-party concrete types do not cross the root facade or Host contracts.
- Every public package commits its generated `pkg.generated.mbti`. CI runs
  `moon info` and rejects an uncommitted interface diff.
- A public API change requires documentation, black-box tests, Native/wasm1
  checks, and explicit review of its generated interface.
- Before 1.0, minor versions may make documented breaking API changes when the
  changelog includes migration guidance. Patch versions do not intentionally
  break public APIs. Starting at 1.0, Semantic Versioning applies normally.
- Serialized data, cache entries, policies, and JSON output use their own
  explicit schema versions and are not covered only by the package version.
- Upstream CLI compatibility and MoonJust library API stability are separate
  contracts. Matching `just 1.57.0` does not require copying its Rust API.

## Consequences

Phase packages can evolve during the alpha period without pretending to be a
stable 1.0 library, while interface drift remains visible in review. The later
facade can hide parser and adapter implementation types. A breaking public
change cannot be smuggled into an internal refactor or snapshot update.
