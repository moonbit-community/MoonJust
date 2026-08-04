# ADR-0009: Wasm support boundary

- Status: Accepted
- Date: 2026-08-04

## Context

MoonJust must run on MoonBit Native and wasm1 so it is usable through
`moonx`/`moonrun`. A command runner needs capabilities that are not inherent to
portable WebAssembly, especially filesystem traversal, environment access,
process spawning, signals, and terminal I/O. Calling all of these environments
"Wasm support" without a boundary would create false portability and security
claims.

## Decision

- `wasm` in the first release means MoonBit's wasm1 backend hosted by
  `moonx`/`moonrun` with an explicit capability policy.
- Pure parsing, formatting, checking, analysis, and planning are required on
  Native and wasm1 and do not require process capability.
- Recipe execution on wasm1 is Tier W: it is enabled only when the host adapter
  reports the required filesystem, environment, and process capabilities.
- Missing or denied capabilities produce typed diagnostics and nonzero mapped
  exit statuses; features are never silently disabled.
- Browser execution, arbitrary WASI runtimes, and wasm-gc process execution are
  outside the first-release claim. wasm-gc may remain a pure-core compile gate.
- Policy files use least privilege and are published as reviewable examples.
  Granting a child-process capability does not sandbox the resulting host child.
- Native and wasm1 share semantic corpora. Target-specific tests must assert a
  nonzero selected count and record approved capability differences.

## Consequences

MoonJust can provide useful library and inspection behavior in hosts that
cannot spawn commands, while full command execution remains honest about its
runtime. Host policy and adapter changes are compatibility and security work.
The narrower capabilities proven in the Phase 0 async spike remain subject to
Windows, TTY, signal, large-I/O, and published-policy release gates.
