# Maintenance Report: Logic Rewrite and CI Recovery

## Scope

This report records the maintenance work that followed the binary-only logic
rewrite. The implementation remains pure MoonBit and the product entrypoint is
the root executable.

## Completed Work

- Restored historical ADRs and engineering reports under
  `docs/development/` without treating them as active contracts.
- Moved the current architecture document to `docs/ARCHITECTURE.md`.
- Moved the MoonBit compatibility, platform, benchmark, and testkit runners
  from `cmd/tests` to `tests`.
- Added pinned just 1.57.0 test inventory and provenance under
  `tests/compatibility/upstream/`.
- Hardened the compatibility runner so manifest identity, expected outcome,
  compared fields, explicit difference reasons, and upstream test anchors must
  agree.
- Kept comparisons byte-exact for status, stdout, stderr, merged output,
  filesystem effects, and declared live-output observations.
- Fixed CI executable resolution after runners change into temporary case
  directories. The testkit resolves path-based programs before execution.

## Validation

Remote CI run `33295810860` passed on Ubuntu, macOS, Windows, Wasm, formatting
and interface checks, and the just 1.57 differential job.

The local compatibility run reported 176 exact matches, 6 explicitly declared
known differences, and 0 failures. Native and Wasm package tests each passed
18 tests.

## Maintenance Boundary

This report documents completed work only. It does not add package, file-layout,
test-count, or architecture assertions to the product contract.
