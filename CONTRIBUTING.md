# Contributing to MoonJust

MoonJust is a binary-only MoonBit project. Production implementation lives in
`internal/`; the root package is the executable entrypoint.

## Local checks

```text
moon update
moon info
moon fmt
moon check --target native
moon check --target wasm
moon test --target native
moon test --target wasm
moon publish --dry-run
```

Behavior changes require focused MoonBit tests. Cross-platform or compatibility
changes should be exercised with the runners in `tests`. Tests compare
observable output, status, filesystem effects, environment, stdin behavior,
and host policy; they do not assert package names, file layout, or source
implementation details.

For official compatibility, install `just 1.57.0` and run the live-oracle
command documented in `tests/compatibility/README.md`. Add a real fixture,
expected result, and upstream source anchor for each new upstream case. Do not
use a test name to synthesize an unrelated justfile, and do not use an
unbounded regex when a deterministic byte comparison is possible. Date/time
outputs must be normalized or regenerated deliberately; stale snapshots are
not compatibility evidence.

Benchmark JSON is diagnostic evidence, not a release claim. Pull requests use
one interleaved batch of 15 samples, while main runs use three batches. Current
CI records the reports but does not pass the optional benchmark `--enforce`
flag, so performance conclusions must quote the artifact's target, runner,
toolchain, sample counts, and ratios.

Keep the phase boundaries explicit: project loading returns a snapshot,
planning returns an execution plan, and runtime executes only that plan.
