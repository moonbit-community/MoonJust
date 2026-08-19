# Host async capability spike

- Date: 2026-08-04
- Dependency: `moonbitlang/async 0.20.4`
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

Adopt exact `moonbitlang/async 0.20.4` as the initial implementation dependency
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

## Linux signal ownership follow-up

The isolated `signal_probe` demonstrates a remaining Linux limitation in
async 0.20.4 and current upstream main. Calling
`set_global_cancellation_signals([])` unblocks the supported signals, but the
event loop still starts a worker that calls `sigwait` for every supported
signal. That worker can consume a process-directed signal before an
application handler, so MoonJust cannot implement official just's
"record INT/HUP/QUIT, forward TERM" contract using the public async signal API
alone. Process spawn, wait, cancellation, and Windows Job Object ownership
remain delegated to async; the Unix compatibility adapter must stay isolated
until async exposes signal observation or configurable wait ownership.

## Original spike limitations

- Windows command construction, cwd, environment, process groups, and Job
  Object cancellation.
- Graceful signal selection/forwarding and escalation timeout.
- TTY inheritance, interactive stdin, terminal size, and color detection.
- Published `moonx` policy profiles and behavior outside `moonrun`.

Phase 9 production adapters now drain stdout/stderr concurrently with an
explicit capture budget and cover file locking, atomic cache publication,
crash recovery and cross-process contention. Symlink authorization races and
the other platform-specific items above remain assigned to Phase 10. This
historical spike does not invalidate its narrower Phase 0 dependency decision.
