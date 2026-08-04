# ADR-0004: Host capability boundary

- Status: Accepted
- Date: 2026-08-04

## Context

Recipe execution needs filesystem, environment, process, terminal, time,
random, and signal facilities. These differ across Native and wasm1, and the
available MoonBit runtime packages are still evolving.

## Decision

- MoonJust owns `HostFs`, `HostEnv`, `HostProcess`, `HostClock`, `HostRandom`,
  `HostTerminal`, `HostSignal`, and `HostPlatform` contracts.
- Pure parsing, analysis, evaluation, and planning packages depend only on
  explicit values or these abstract contracts, never target FFI.
- Native and wasm1 implementations live in separate leaf adapters.
- Third-party errors and concrete resource types do not cross the `host`
  boundary.
- `moonbitlang/async` is a candidate adapter implementation, not a public API.
  Exact adoption depends on the Phase 0 capability spike.
- A missing capability returns a typed denied/unavailable error. It does not
  masquerade as a recipe exit failure.
- wasm1 execution means `moonx`/`moonrun` with explicit policy. It does not mean
  browser or arbitrary WASI support.

## Consequences

The project can offer parse/check/format APIs with no process capability. Async
runtime upgrades remain localized, fake hosts can make tests deterministic, and
Wasm policy limitations are visible. Allowing a Wasm child process must not be
advertised as sandboxing that child.
