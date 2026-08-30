# ADR-0012: Phase 7 filesystem transactions

- Status: Accepted
- Date: 2026-08-07

## Context

Formatting and initialization must not expose a partially written justfile.
Temporary files must be cleaned after conflicts, permission failures, and
cancellation. Native and moonrun wasm1 have different execution models: the
Native adapter can complete a synchronous operating-system transaction, while
the policy-aware wasm1 rename API in `moonbitlang/async 0.20.3` is asynchronous.
Calling WASI directly would bypass moonrun's documented filesystem policy and
is therefore not an acceptable adapter.

Windows also requires wide-character paths and handle-based canonicalization;
`_fullpath` is only lexical and does not resolve symbolic links.

## Decision

- `HostTemp` owns same-directory temporary creation and cleanup. `HostFs`
  owns the final persist operation, and the synchronous `write_file_atomic`
  helper composes both contracts for Native and deterministic fake hosts.
- `HostAtomicFs` is the project-owned asynchronous transaction contract. The
  wasm-only `host_wasm/transaction` leaf implements it with the fixed
  `moonbitlang/async` filesystem create, remove, and rename operations.
- Temporary files are created exclusively with mode `0600`, fully written and
  synchronized before commit, and named with host random bytes. Commit either
  atomically replaces the destination or atomically refuses an existing path.
- Native overwrite preserves the destination's POSIX mode. A read-only target
  produces `PermissionDenied(FsWrite)` instead of silently replacing it.
- Failed commits perform cancellation-protected best-effort cleanup without
  hiding the original typed error. No file contents or environment values are
  included in diagnostics.
- Windows Native paths use UTF-16. Canonicalization opens the object and calls
  `GetFinalPathNameByHandleW`, so symbolic-link identity is physical rather
  than lexical.
- The Phase 6 `ReadOnlyFs` remains the default wasm inspection adapter and
  returns `CapabilityDenied(FsWrite)`. Adding the writable transaction adapter
  does not broaden the published inspection policy.

## Consequences

`fmt` and `init` use atomic transactions on Native and fake hosts. A future
writable wasm CLI composition can await `HostAtomicFs` without introducing an
async runtime into parser, formatter, loader, or application packages. The
wasm transaction package supports wasm1 only; wasm-gc, JavaScript, browsers,
and arbitrary WASI runtimes remain outside the support claim.

The filesystem policy probe must pass both an allow policy and the read-only
inspection policy. Native platform tests cover exact CRLF bytes, symbolic-link
identity, permission rejection, no-overwrite behavior, and temporary cleanup.
