# Host async capability spike

- Date: 2026-08-04
- Dependency: `moonbitlang/async 0.20.3`
- License: Apache-2.0
- Toolchain: `moon 0.1.20260803`, `moonc 0.10.6+62c2592d1`
- Development host: macOS 26.5.2 arm64, Unix `/bin/sh`
- Tested targets: `native`, `wasm` (wasm1 through `moonrun`)
- Source: `spikes/host-async`

## Question

Can MoonJust implement the first Native and moonrun wasm1 HostFs/HostProcess
adapters using the official async package without exposing that experimental
API to core packages?

## Result

| Contract | Native | wasm1 | Evidence |
| --- | --- | --- | --- |
| child exit status | Pass | Pass | child exits 7, API returns 7 |
| stdout capture | Pass | Pass | exact `stdout` bytes |
| stderr capture | Pass | Pass | exact `stderr` bytes |
| cwd | Pass | Pass | child reads fixture from supplied directory |
| extra environment | Pass | Pass | child observes explicit value |
| filesystem create/read | Pass | Pass | temp file round trip |
| stdin pipe | Pass | Pass | exact bytes through `cat` |
| hard cancellation | Pass | Pass | 10-second child cancelled by 100 ms timeout |

Both target runs selected four tests and passed all four. This avoids the
earlier false-positive risk where a successful command selected zero tests.

## Important observations

1. On macOS, the temp API returned `/tmp/...` while the child reported
   canonical `$PWD` as `/private/tmp/...`. The host model must distinguish a
   user/display path from canonical filesystem identity.
2. The wasm1 test runner can spawn host processes, but production execution
   still requires explicit `moonrun` policy. Test-runner permission is not a
   publish-time guarantee.
3. A spawned child is a host process. Parent Wasm fs/env/net restrictions do
   not automatically create a complete child-process sandbox.
4. `moonbitlang/async` remains experimental. Its types and errors must be
   translated at the MoonJust `host` boundary.
5. The package does not establish wasm-gc process support; wasm-gc remains a
   pure-core check target.

## Decision

Adopt exact `moonbitlang/async 0.20.3` as the initial implementation dependency
for Native and wasm1 filesystem/process adapters, subject to these controls:

- Keep the dependency in leaf adapters and never expose its concrete types.
- Maintain a fake Host implementation for deterministic core tests.
- Run the spike contract in CI until equivalent production adapter tests
  replace it.
- Treat dependency updates as compatibility changes with the full process/fs
  matrix.
- Prefer an upstream fix for package defects; fork only with an explicit patch
  queue and license record.
- Do not enable a second default runtime implementation in parallel.

## Not yet proven

- Windows command construction, cwd, environment, process groups, and Job
  Object cancellation.
- Graceful signal selection/forwarding and escalation timeout.
- TTY inheritance, interactive stdin, terminal size, and color detection.
- Large-output backpressure and concurrent stdout/stderr ordering.
- File locking, symlink races, atomic rename semantics, and cache contention.
- Published `moonx` policy profiles and behavior outside `moonrun`.

These gaps are assigned to Phase 7-10 and block the corresponding compatibility
tier; they do not invalidate the narrower Phase 0 dependency decision.
