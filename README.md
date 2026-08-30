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
`host_native` and `host_wasm` implement platform boundaries, and
`host_testkit` is test-only. Project loading produces an immutable snapshot;
planning never starts a process and runtime never reparses a justfile.

## Compatibility checks

The pure MoonBit runners under `cmd/tests` compare observable behavior with an
official just 1.57 binary and exercise platform boundaries. For a local paired
run:

```text
moon run --target native ./cmd/tests/compat -- --candidate PATH --official PATH
moon run --target native ./cmd/tests/benchmark -- --candidate PATH --official PATH --rounds 15
```

Only functional behavior is tested: bytes written to stdout and stderr,
status codes, file effects, environment, stdin timing, and platform policy.
