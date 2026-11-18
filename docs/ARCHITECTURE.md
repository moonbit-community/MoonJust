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

## Invariants

- Project loading cannot start a process or write command output.
- Query cannot mutate the project or construct runtime tasks.
- Planner cannot import a concrete process adapter.
- Runtime receives an existing plan and cannot import lexer, parser, or loader.
- Host contracts do not depend on cache implementations or test doubles.
- Loading caches end before recipe execution; execution observes file changes.

## Verification

The Native test tools under `tests/` drive the Wasm artifact. Strict coverage runs the MoonBit spec tests and outlines with `--target wasm`, then merges differential results by upstream identity across three hosts. See [the runner contract](../tests/compatibility/README.md) and [the migration evidence](maintenance/WASM_MIGRATION.md).
