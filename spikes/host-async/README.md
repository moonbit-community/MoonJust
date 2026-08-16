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
