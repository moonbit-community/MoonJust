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

Keep the phase boundaries explicit: project loading returns a snapshot,
planning returns an execution plan, and runtime executes only that plan.
