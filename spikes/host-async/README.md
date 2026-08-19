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

On Linux, `check_signal_ownership.sh` verifies the boundary used by MoonJust:
after global async cancellation signals are disabled, the application handler
must receive HUP, INT, QUIT, and TERM. Each signal is sampled five times and
reported separately. Any lost signal fails the spike instead of being inferred
from the larger upstream process-tree test.
