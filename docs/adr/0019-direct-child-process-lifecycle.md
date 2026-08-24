# ADR-0019: Direct-child process lifecycle and C-free Wasm execution

- Status: Proposed
- Date: 2026-08-24
- Issue: [MoonJust #58](https://github.com/moonbit-community/MoonJust/issues/58)

## Context

MoonJust currently contains a private Unix process-group path in
`src/host_process/process_group.c`, `src/host_process/process_group.mbt`, and
the process adapter. For selected non-interactive commands it starts a
MoonJust helper, calls `setpgid(0, 0)` before `execvp`, and later sends
`SIGTERM`/`SIGKILL` to the group.

This path was introduced to clean up descendants that inherit the recipe's
output pipes. It is not a complete process-tree boundary: a recipe can call
`setpgid` or `setsid`, detach a process, or intentionally leave a background
job running. It also adds a native-only C path, so the same lifecycle cannot be
used by the Wasm/MoonX backend.

The upstream `just 1.57.0` behavior is narrower. It tracks, signals, waits
for, and reaps direct recipe children. HUP/INT/QUIT rely on normal foreground
process-group delivery, while TERM is forwarded to tracked direct child PIDs.
Upstream does not promise containment or cleanup of every indirect descendant.

The previous parent-side `setpgid(child_pid, child_pid)` experiment is not a
valid basis for this design because the parent can race the child's `exec` or
exit. The current child-side helper avoids that particular race, but it still
does not provide complete containment and remains outside the upstream
behavior.

## Decision

Remove MoonJust's private process-group feature and use
`moonbitlang/async/process` for the common Native and Wasm/MoonX path.

The production contract becomes:

1. `@process.spawn` creates the direct recipe child.
2. async owns process creation, cancellation, waiting, reaping, and pipe
   resources.
3. MoonJust supplies the cancellation policy and preserves the child's exit
   status and signal mapping.
4. Cancellation must terminate the direct child gracefully according to the
   async cancellation handler, then forcefully if the handler's grace period
   expires.
5. Terminal-generated HUP/INT/QUIT behavior follows the host's foreground
   process-group semantics. TERM is forwarded according to MoonJust's
   direct-child policy.
6. MoonJust does not promise to terminate detached, daemonized, regrouped, or
   otherwise indirect descendants.

This ADR does not change the Unix signal-observation design in
`signal_forward.c`. Signal capture and the just-specific HUP/INT/QUIT/TERM
policy remain a separate decision until async exposes the required signal
event or cancellation-cause surface.

## Scope of removal

The implementation change covered by this ADR will remove:

- `src/host_process/process_group.c` from the native stub list;
- `src/host_process/process_group.mbt` and its helper command flag;
- process-group readiness polling, group signaling, and group cleanup from
  `src/host_process/process.mbt`;
- process-group initialization and helper dispatch from `cmd/just`;
- process-group-specific tests, fixtures, and release claims.

The process adapter will retain one `ObservedProcess` representation backed by
`@process.Process`. No public API or generated interface changes are allowed.

`signal_forward.c` currently also contains a native file-descriptor kind helper.
That helper must be moved behind an existing async/host capability or isolated
in a separately reviewed adapter before the file is removed in a later signal
change. It is not silently duplicated in this migration.

## Lifecycle and output rules

The direct-child lifecycle and pipe lifecycle are separate observations:

- `Process::wait` proves that the direct child exited and was reaped;
- a pipe reader reaching EOF proves that all writers for that pipe have
  closed, which may include indirect descendants;
- a descendant holding a shared pipe is not evidence that async failed to reap
  the direct child.

Readers must continue to run concurrently with the direct-child wait. The
adapter must not claim whole-tree containment merely because a pipe reader
eventually reaches EOF. If an indirect descendant keeps a pipe open, the
resulting behavior must be compared with upstream `just` and documented; it
must not be fixed by reintroducing an implicit process-group kill.

## Verification plan

Before deleting the implementation, add or retain target-specific tests for:

- direct child normal exit and signal exit status;
- cancellation of a direct child and completion of `Process::wait`;
- a shell that starts a foreground child;
- a background child that remains after the direct shell exits;
- a deliberately detached `setsid` descendant, which is allowed to survive;
- concurrent stdout/stderr draining while the direct child is running;
- comparison of background-recipe behavior with official `just 1.57.0`.

The Linux reproducer must record PID, PPID, PGID, direct-child wait status,
pipe-holder evidence, and the final reader state. Its hard lifecycle gate is
direct-child cancellation, wait, and reap. Indirect descendants are reported
as an explicit observation class rather than treated as an async ownership
failure.

The migration is accepted only when all of the following hold:

- Native and Wasm/MoonX builds no longer reference the process-group helper;
- `moon check --target all --warn-list +73` passes;
- native and wasm process tests pass;
- the official non-completion differential suite has no new unapproved
  failure;
- direct-child cancellation and reap pass on Linux and macOS;
- Windows and Wasm use the same async process contract without Unix-only
  branches;
- `.mbti` files and the stable public API are unchanged;
- release documentation no longer claims whole-tree process containment.

## Consequences

Positive consequences:

- one process lifecycle implementation for Native and Wasm/MoonX;
- no MoonJust process-group C or helper executable path;
- behavior is closer to official `just`;
- intentional background jobs are not automatically killed by MoonJust's
  private group policy.

Trade-offs:

- ordinary indirect descendants may survive after their direct shell exits;
- a descendant may keep a shared output pipe open;
- detached or regrouped descendants cannot be guaranteed to terminate;
- signal handling remains a separate native concern until async gains a
  suitable observation API.

These trade-offs are part of the proposed compatibility contract and must be
visible in the platform and release evidence rather than hidden by broad
normalization or process-tree cleanup claims.

## Rollback

If direct-child cancellation, waiting, or exit-status mapping regresses, revert
the implementation change before release. Do not restore the parent-side
`setpgid` retry approach. Any future process-tree capability must be introduced
as a separately reviewed async or host-capability design with Native and Wasm
semantics defined together.
