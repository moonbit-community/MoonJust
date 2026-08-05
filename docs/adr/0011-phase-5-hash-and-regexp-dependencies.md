# ADR-0011: Phase 5 hash and regexp dependencies

## Status

Accepted

## Context

Phase 5 needs SHA-256, BLAKE3, and regular-expression matching on both Native
and wasm1. The project plan requires exact versions, target evidence, and an
adapter boundary for every non-core dependency. User-visible BLAKE3 semantics
must never be replaced with SHA-256.

## Decision

- Adopt `moonbitlang/x@0.4.47` only for its `x/crypto` SHA-256 implementation.
  The import is confined to `src/builtin` and the public API exposes strings,
  not the dependency's concrete types.
- Adopt `moonbitlang/regexp@0.3.5` only behind the `regex_matches` builtin. Its
  compile errors are converted to `BuiltinError::InvalidPattern`.
- Maintain BLAKE3 as a small pure MoonBit implementation in `src/builtin`.
  It follows the official 7-round compression, chunk tree, parent, and root
  output rules and is validated with official vectors, including a multi-chunk
  input.

Both dependencies are official MoonBit packages with Apache-2.0 licensing and
are locked in `moon.mod`. No community package or native FFI crosses the core
boundary.

## Consequences

The evaluator remains cross-target and deterministic, and the hash functions
can be tested with fake hosts. The current file-hash implementation obtains the
complete file through `HostFs`; a future streaming HostFs API can optimize this
without changing the builtin contract.

## Rollback

Remove the two exact imports and their adapter calls, retain the pure BLAKE3
implementation, and mark regexp/SHA-256 as typed unsupported in the compatibility
manifest. Any version upgrade requires fresh Native/wasm checks and vector
tests.
