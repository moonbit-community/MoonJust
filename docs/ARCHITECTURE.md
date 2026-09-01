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

Static `--help` and `--version` requests end before Host initialization. Wasm
summary/check/format requests may use the target adapter's synchronous fast
path; a rejected fast path returns to the same application chain without
changing errors or output order.

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
        ├── native
        ├── process
        ├── wasm
        │   └── transaction
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

The `host/wasm` package has a Native-only `ReadOnlyFs` branch for compiling its
inspection adapter on Native. The Wasm branch wraps `PortableHost`; no Wasm
runtime path calls the Native implementation.

## File organization

Root files are fixed by target responsibility:

```text
main.mbt                 shared routing and final output
runtime_native.mbt       Native Host and exit adapter
runtime_portable.mbt     Wasm Host, exit adapter, and safe fast paths
```

Within `application`, files are named for lifecycle responsibility:
`routing`, `project_preparation`, `planning`, `responses`, and `errors`.
Target-specific implementations use `_native` or `_portable`; async Host
boundaries use `_async` only when the synchronous path has different
capabilities. `trait_extensions.mbt` is reserved for package-local extension
methods and does not contain orchestration.

## Invariants

- Project loading cannot start a process or write command output.
- Query cannot mutate the project or construct runtime tasks.
- Planner cannot import a concrete process adapter.
- Runtime receives an existing plan and cannot import lexer, parser, or loader.
- Host contracts do not depend on cache implementations or test doubles.
- Native/Wasm differences are selected at root or Host leaves, never by hidden
  global behavior in domain packages.
- Loading caches end before recipe execution; execution observes file changes.

## Verification

All executable verification tools are MoonBit packages under `tests/`.
`tests/compat` compares status, stdout, stderr, merged streams, filesystem
effects, and live-output observations against just 1.57.0. Existing known
differences are restricted by field and pinned candidate SHA-256. `tests/platform`
runs a cross-platform candidate/oracle differential, and `tests/benchmark`
uses interleaved paired samples after verifying workload output equivalence.

The current strict compatibility report covers 2,417 upstream identities:
2,358 exact, four pinned known differences, 34 completion exclusions, 21
runtime-signal exclusions, and zero unclassified identities. The executable
black-box corpus has 1,417 scenarios (1,411 exact and six known differences
across all supported platforms). A Unix run reports 1,410 exact scenarios when
the one Windows-only case is skipped; that case is executed on the Windows
matrix job.

Benchmark reports include the runner, architecture, Moon/Moonc/Moonrun
versions, workload size, raw sample counts, median/p95 ratios, and confidence
intervals. They are currently observational artifacts: pull requests run one
batch of 15 samples, main runs use three batches, and CI does not invoke the
optional `--enforce` flag. Date-sensitive compatibility snapshots are
supplementary to the live official oracle and must not be treated as immutable
golden output.
