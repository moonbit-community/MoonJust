# MoonJust

MoonJust is a standalone MoonBit executable compatible with just 1.57. It has
no supported library facade: the product is the binary at the repository root.

## Build and run

```text
moon update
moon check --target native
moon test --target native
moon build --release --target native .
moon run . -- --help
moon build --release --target wasm .
```

The generated executable is the root package `MoonJust`; its exact filename is
chosen by the target toolchain.

## Execution model

The binary follows one data flow:

```text
main -> cli.parse_invocation -> application.classify_request
     -> project.load_snapshot -> query | planner
     -> runtime.execute_plan -> application.render_response
```

Implementation packages live below `internal/`. `host` defines capabilities,
`host/native` and `host/wasm` implement platform boundaries, and
`host/testkit` is test-only. Project loading produces an immutable snapshot;
planning never starts a process and runtime never reparses a justfile.

## Compatibility checks

The pure MoonBit runners under `tests` compare observable behavior with an
official just 1.57 binary and exercise platform boundaries. For a local paired
run:

```text
moon run --target native ./tests/compat -- --candidate PATH --official PATH
moon run --target native ./tests/platform -- --candidate PATH --official PATH
moon run --target native ./tests/benchmark -- --candidate PATH --official PATH --rounds 15
```

Only functional behavior is tested: bytes written to stdout and stderr,
status codes, file effects, environment, stdin timing, and platform policy.

Current architecture lives in `docs/ARCHITECTURE.md`. Maintenance-era reports
live in `docs/maintenance/`; historical ADRs and development reports remain
available under `docs/development/`.
