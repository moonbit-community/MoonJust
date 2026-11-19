# Architecture

MoonJust is a binary-only MoonBit project. The root package owns the executable
entrypoint; every reusable implementation package is private under `internal/`.

## Execution chain

```text
main
  -> application.classify_request
  -> application.prepare_project
  -> project.load_snapshot
  -> query | planner
  -> runtime.execute_plan
  -> application.render_response
  -> main.write_and_exit
```

Static help and version responses bypass project loading. Other commands enter one asynchronous application chain; there is no synchronous Wasm fast path.

`application` is the only orchestration package. It owns routing, invocation
facts, error conversion, response assembly, and the hand-off between project,
query, planner, and runtime. Domain packages never import it.

## Package map

```text
MoonJust (root executable)
└── internal/application
    ├── cli
    ├── project ── loader ── parser ── lexer
    │           └─ semantic ── evaluator ── builtin/value
    ├── query
    ├── planner ── invocation/environment/cache
    ├── runtime ── planner/cache
    └── host
        ├── fs
        ├── process
        ├── wasm
        └── testkit (tests only)
```

Supporting value packages are `source`, `syntax`, `diagnostic`, `path`,
`modulepath`, and `workdir`. They contain data models and pure transformations,
not application routing or process creation.

## Ownership

- `cli`: argument grammar, environment-backed options, validation, and response
  values. It does not read a justfile.
- `loader`: discovery, bounded source reads, canonical paths, imports, and the
  loaded module graph.
- `semantic` and `evaluator`: declarations, validation, scopes, settings,
  values, and explicitly capability-gated effects.
- `project`: immutable project input, source graph, semantic compilation, and
  working-directory facts shared by query and planning.
- `query`: read-only result models, deterministic ordering, display width, and
  rendering support.
- `planner`: dependency traversal, recipe expansion, dry-run eligibility,
  scripts, scheduling data, and `ExecutionPlan` construction. It never starts a
  process.
- `runtime`: captured/live I/O, task coordination, cache execution,
  cancellation, and process result conversion. It never reloads or reparses a
  project.
- `host`: capabilities, errors, and boundary value types only. `host/fs`
  contains reusable file algorithms; the remaining children implement concrete
  adapters.

The root `main.mbt` selects the host, forwards standard streams and exits with the application status. `host/wasm` owns filesystem and host facts; `host/process` owns child lifetime and stdio. Both use standard MoonBit APIs; production packages target linear-memory Wasm only. Native test drivers do not supply filesystem or process implementations to the product.

Automatic color uses the terminal state of the selected output stream. The Wasm host probes inherited standard handles on first use, using `test -t` on Unix and the console redirection properties on Windows. When the host denies the probe, automatic color is disabled. Explicit color modes work in either environment.

Command timestamps use the wall clock at command echo. On Unix the Wasm host evaluates POSIX `TZ` offsets and transition rules at that instant. It also accepts named and absolute TZif files and reads the system zone from `/etc/localtime` when `TZ` is unset. An empty `TZ` selects UTC. On Windows it queries the system time zone for the instant being formatted. UTC formatting requires only the clock.

The embedded changelog is the output of `just --changelog` for the pinned 1.59.0 release (CC0, upstream commit `2638e9c0941edb1f409da7426fa7842887656973`). Its contract test checks the complete UTF-8 byte sequence by size and SHA-256.

## Invariants

- Project loading cannot start a process or write command output.
- Query cannot mutate the project or construct runtime tasks.
- Planner cannot import a concrete process adapter.
- Runtime receives an existing plan and cannot import lexer, parser, or loader.
- Host contracts do not depend on cache implementations or test doubles.
- Loading caches end before recipe execution; execution observes file changes.

## Verification

The Native test tools under `tests/` drive the Wasm artifact and the pinned official CLI. The runner records differential observations and upstream document checks separately. It verifies indexed local specs and smoke assertions with the Wasm test suite and outline. The merger checks the evidence kind and execution state of each upstream identity across Linux, macOS and Windows. [Runner contract](../tests/compatibility/README.md)
