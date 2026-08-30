# ADR-0020: Async-only Unix signal semantics

- Status: Accepted
- Date: 2026-08-25

## Context

MoonJust previously added `src/host_process/signal_forward.c` to observe Unix
signals, record the first signal, forward `SIGTERM` to direct children, and
feed signal events to MoonBit through a pipe. This was an application-owned
signal runtime layered on top of `moonbitlang/async`.

The current public async API provides process spawn, wait, pipe ownership, task
cancellation, and graceful direct-child cancellation. It does not provide a
stable application-level API for observing a sequence of raw signals without
cancelling the main task. Reimplementing that missing observation layer in
MoonBit alone is not possible: installing a POSIX signal disposition and
receiving a signal event require a host/runtime boundary.

The project accepts a limited weakening of Unix signal semantics and signal
exit codes. The product must therefore prefer one shared async process
lifecycle over a second, MoonJust-specific native signal runtime.

This ADR supersedes the signal-observation reservation in ADR-0019. The
direct-child lifecycle decision in ADR-0019 remains in force.

“Pure MoonBit” in this ADR means that MoonJust owns no signal C FFI or signal
handler. The async dependency may still contain its own native runtime support;
that implementation detail is outside MoonJust's host-process API.

## Decision

MoonJust will use an async-only signal and process model:

1. `moonbitlang/async/process` owns process creation, direct-child
   cancellation, waiting, reaping, and pipe resource ownership.
2. MoonJust will not install a Unix signal handler, create a signal pipe, or
   observe a raw signal sequence.
3. MoonJust will not promise to record the first parent signal or reproduce
   the official `just` sequence of “non-forwarded signal followed by TERM”.
4. The async global cancellation configuration is the only signal policy used
   by MoonJust. Its configured signal set must be explicit and tested for each
   target; an empty set means only that async will not use those signals for
   global cancellation. It must not be documented or treated as equivalent to
   `SIG_IGN`.
5. When async cancellation interrupts a process wait, MoonJust maps the
   result through a generic cancellation/interruption path. It must not invent
   an exact raw signal number that was never observed.
6. Ordinary command failures, ordinary infallible non-zero exits, timeouts,
   direct-child cleanup, and normal output draining remain supported.
7. Detached, regrouped, daemonized, or otherwise indirect descendants remain
   outside the lifecycle guarantee. The guarantee is limited to the direct
   child owned by async.

This decision does not change the stable public API or the official
compatibility baseline. It changes the approved compatibility classification
for the affected Unix signal scenarios.

## Accepted compatibility differences

The following are explicit limitations of the async-only mode:

- Parent-only `SIGHUP`, `SIGINT`, and `SIGQUIT` observation is not supported.
- The official first-signal rule is not guaranteed when multiple signals are
  sent to the MoonJust process.
- Exact `SIGTERM` forwarding from a parent signal event is not guaranteed by
  MoonJust; async's direct-child cancellation policy applies instead.
- Signal-specific exit codes, interruption diagnostics, and exact return
  timing may differ from `just 1.57.0`.
- `[continue]` and macOS/BSD `SIGINFO` behavior are unsupported.
- Signal-triggered `infallible` behavior is not required to clear a parent
  signal and continue exactly as upstream does.

These cases must be reported as approved compatibility differences, not as
`exact`, `diagnostic-exact`, or `not-applicable`. Static signal-number and
exit-code contracts that do not require live signal observation remain
independently testable.

## Implementation scope

The migration must:

- remove MoonJust's signal FFI declarations and signal-pipe state from
  `src/host_process/signal.mbt`;
- remove `signal_forward.c` from the native stub list and delete it once all
  remaining symbols have been replaced;
- replace any unrelated helper still provided by that file, such as native
  file-descriptor classification, with an existing async/host capability;
- remove MoonJust-specific `caught_signal`, `forward_signal`, and signal
  observer branches from `src/host_process/process.mbt`;
- handle async cancellation in the process wait path without depending on a
  previously observed raw signal;
- keep one `ObservedProcess` implementation for native and Wasm/MoonX wherever
  the async API supports the same contract;
- leave the stable package interface and generated `.mbti` files unchanged.

No process-group, `fork`/`exec`, `waitpid`, signal-handler, or pipe-reader
replacement may be added as part of this migration. Any future raw-signal API
must be introduced by async or by a separately approved host-capability ADR.

## Verification requirements

Before deleting the C implementation, the migration must pass:

- `moon check --target all --warn-list +73`;
- native and Wasm/MoonX process spawn, wait, timeout, and direct-child
  cancellation tests;
- concurrent stdout/stderr draining with an explicit EOF check;
- repeated direct-child cancellation tests proving wait completion and no
  zombie direct child;
- foreground-terminal interruption tests documenting the selected async
  policy;
- a direct-PID signal matrix whose expected deviations are listed by exact
  upstream test ID;
- the official non-completion differential harness with no new unapproved
  failures;
- no `.mbti` changes and no MoonJust-owned native signal symbols in the final
  artifact.

The test evidence must separately record direct-child cleanup and indirect
descendant behavior. A surviving indirect descendant or an open pipe held by
that descendant must not be misreported as an async direct-child wait failure.

## Consequences

Positive consequences:

- no MoonJust-specific Unix signal runtime;
- no native signal C stub in the product package;
- one async-owned process lifecycle for native and Wasm/MoonX;
- less platform-specific code and fewer signal-mask/order races;
- direct-child cancellation and reaping use the same implementation as the
  async dependency.

Trade-offs:

- strict upstream Unix signal forwarding is no longer a product guarantee;
- signal identity and signal-derived exit diagnostics can be weaker;
- `[continue]`, SIGINFO, and signal-triggered infallible continuation are
  outside the supported compatibility subset;
- indirect descendants may survive or retain a shared output pipe.

The release evidence and user documentation must state these limitations
plainly. They must not be hidden by broad output normalization or reported as
full official compatibility.

## Rollback

If async fails to clean up a direct child, complete `Process::wait`, close its
owned pipes, or provide a stable native/Wasm contract, stop the migration and
fix or pin the async dependency before release. Do not restore the old
MoonJust-specific signal handler as an unreviewed patch. Reintroducing exact
raw-signal observation requires a new async API or a new ADR with native and
Wasm behavior defined together.
