# Host async spike

This nested module evaluates `moonbitlang/async` as an implementation detail for
MoonJust's Native and wasm1 host adapters. It is intentionally separate from
the production module so an experimental dependency cannot leak into the core
API or normal build graph.

Run on Unix-like development hosts:

```bash
moon -C spikes/host-async test --target native
moon -C spikes/host-async test --target wasm
```

The test uses `/bin/sh` to keep the process behavior controlled. It does not
claim Windows coverage; Windows command and cancellation behavior requires a
separate platform contract suite.

On Linux, `check_signal_ownership.sh` also records the current async 0.20.4
signal-ownership limitation. The event loop's `sigwait` worker can consume a
process-directed signal even after global cancellation is configured with an
empty signal set, so an application-level handler cannot reliably coexist
with it. The probe fails when that limitation becomes stale.
