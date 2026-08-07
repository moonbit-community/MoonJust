# Phase 6 completion report

- Status: Implementation complete; remote CI and second audit pending
- Date: 2026-08-07
- Upstream baseline: `just 1.57.0` at `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Required targets: Native and wasm1
- Release identity: `0.3.0-alpha.0`

Phase 6 delivers a query-oriented CLI for checking, formatting, initializing,
and inspecting justfiles. It deliberately does not execute recipes and is not a
production runner. Query composition depends only on `HostFs`; no query API can
receive `HostProcess`.

## Delivered contracts

| Unit | Delivery | Evidence |
| --- | --- | --- |
| PR-060 | Declarative argparse inventory, command exclusivity, requires/conflicts, aliases, value validation, stable unsupported errors | `src/cli/arguments.mbt`, 10 CLI tests |
| PR-061 | check/fmt/init, stdin formatting, no-overwrite init, failure-before-write | `src/application/format.mbt`, FakeHost mutation tests |
| PR-062 | list/show/summary/usage/groups, aliases, docs, private/group filtering, source and lexical order, Unicode width | `src/application/query.mbt`, application and white-box width tests |
| PR-063 | pure evaluate, variables, canonical dump, versioned stable JSON, shell output, effect rejection | `src/application/inspect.mbt`, schema and deterministic-output tests |
| PR-064 | Native CLI composition, Wasm read-only adapter and deny-by-default inspect policy | `src/host_wasm`, `policies/inspect.toml`, `tools/check_phase6_inspect.sh` |

## Compatibility evidence

- All 50 upstream options and 19 command entries are inventoried. Implemented
  entries are marked as such; all other entries are rejected with a stable
  unsupported error or explicitly excluded. No unknown option is ignored.
- The pinned upstream test map assigns 86 Phase 6 registrations to executable
  Native/wasm anchors, explicitly excludes 30 completion registrations, and
  records five product-maintenance registrations as not applicable. Cases that
  require module graph composition, search/working-directory state, invocation,
  terminal rendering, runtime, cache, or editor capabilities remain explicitly
  owned by their later phases.
- Baseline differential cases for list, evaluate, summary, and explicit
  justfile queries are byte-for-byte matches. Version remains an intentional
  product-identity difference. Later-phase recipe execution cases remain
  explicit expected differences.
- JSON schema version 1 covers root-module assignments, aliases, recipes,
  settings, expression nodes, source identity, recipe attributes, unexports,
  and warnings with deterministic lexical map order. Loaded submodule graph
  serialization remains owned by Phase 7 and is not counted as Phase 6
  evidence.
- Effectful evaluate fails with `EffectRequired`; it never receives a process
  capability.

## Wasm boundary

`ReadOnlyFs` implements only `HostFs`. Its write method always raises
`CapabilityDenied(FsWrite)`, and the package has no `HostProcess`, `HostEnv`,
clock, random, terminal, or signal implementation. `policies/inspect.toml`
allows repository reads, denies writes and networking, imports no environment,
and sets process spawn to false.

The executable policy test builds the real wasm CLI and verifies:

1. list produces the expected stdout and no stderr;
2. format exits nonzero, reports typed write denial, and preserves the file;
3. effectful evaluate exits nonzero and does not create a process marker.

## Verification

- `moon check --target all --warn-list +73`: pass.
- `moon test --target native`: 134 passed, 0 failed.
- `moon test --target wasm`: 133 passed, 0 failed.
- `tools/differential/real_smoke.sh`: 4 matches, 6 classified differences,
  0 failures.
- `tools/check_phase6_inspect.sh`: pass.
- `tools/check_phase6_oracle.sh`: 24 Native/Wasm query cases match the pinned
  upstream oracle byte-for-byte.
- `tools/check_architecture.sh`: fifteen core packages and two adapter leaves.
- `moon info && moon fmt`: generated interfaces refreshed and formatting clean.

## Publication evidence

PR URLs, remote CI runs, merge commits, post-merge CI, and the independent
second-audit verdict are recorded here after the remote delivery cycle.
