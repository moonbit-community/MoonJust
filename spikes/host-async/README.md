# Host async spike

This nested module is a historical and isolated evaluation of
`moonbitlang/async` for MoonJust's Native and wasm1 host adapters. It is
intentionally separate from the production module and is not part of the
current production build or release gate.

Run on Unix-like development hosts:

```bash
moon -C spikes/host-async test --target native
moon -C spikes/host-async test --target wasm
```

The test uses `/bin/sh` to keep the process behavior controlled. It does not
claim Windows coverage; Windows command and cancellation behavior requires a
separate platform contract suite.

On Linux, `check_signal_ownership.sh` records the historical signal-ownership
boundary used during the async capability investigation. It does not describe
the current MoonJust contract: production uses async-owned cancellation signals
and does not install a MoonJust signal handler or raw signal observer.

`check_process_lifecycle.py` records the signal-to-cancellation path and runs
direct-child, shell-`exec`, ordinary foreground shell, and background shell
descendant scenarios, plus a direct-child case where signal ownership is
configured at the first async-main statement instead of during module init.
Each case captures PID, PPID, PGID, process state, and Linux pipe holders before
cleanup. The driver always starts an isolated test session and kills that exact
group on failure, so the evidence run cannot leave its own descendants behind.

The production adapter evidence is collected separately by
`check_moonjust_process_lifecycle.py`. It records normal direct-child exit,
direct-child cancellation and reap, a background descendant, and a detached
`os.setsid()` descendant. On Linux it reads pipe holders from `/proc`; on
macOS it uses `lsof`. Background and detached survival, including a shared-pipe
holder, is an explicit observation rather than a failure; the harness cleans
the isolated session and known descendant PID afterward.

The lifecycle report is valid only when PID observation is available.
If a host forbids `ps` (for example, a restricted local sandbox), the report is
emitted with `status: infrastructure-invalid` and a non-zero exit status; this
must not be interpreted as a lifecycle pass. Linux CI uses `/proc` and `ps` and
enables the full assertion set.
