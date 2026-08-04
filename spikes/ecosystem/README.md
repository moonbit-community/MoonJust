# Parser ecosystem spike

This nested module validates candidate source, regexp, CommonMark, and time
APIs without adding them to MoonJust's production dependency graph.

```bash
moon -C spikes/ecosystem test --target native
moon -C spikes/ecosystem test --target wasm
moon -C spikes/ecosystem bench --target native --release
moon -C spikes/ecosystem bench --target wasm --release
```

Benchmarks are observations and are not part of the deterministic CI gate. The
dependency decisions, measurements, and known gaps are recorded in
`docs/spikes/parser-ecosystem.md`.
