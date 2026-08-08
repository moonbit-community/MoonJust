# Phase 6 completion report

- Status: Implemented; Phase 6 exit passed
- Date: 2026-08-07
- Strict second review: passed against `main` at
  `8e9a3830d5e643c0e209db5a142c27d457932bb9`
- Historical phase snapshot; the current cross-phase verdict is in
  [`PHASE_0_7_AUDIT.md`](PHASE_0_7_AUDIT.md).
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
| Second-audit remediation | Query error contracts, repeated groups, option-aware list/usage, init path selection, fmt/init streams, complete root JSON fields, honest case ownership | 24 Native/Wasm oracle cases and 134/133 full tests |

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
  serialization remains a later serialization contract and is not counted as
  Phase 6 evidence.
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

| Delivery | Merge commit | PR CI | Post-merge `main` CI |
| --- | --- | --- | --- |
| [PR #21 / PR-060](https://github.com/moonbit-community/MoonJust/pull/21) | `1e90e3724f9871aa292dc63348c12caa6f27b791` | [31157708464](https://github.com/moonbit-community/MoonJust/actions/runs/31157708464) | [31157971210](https://github.com/moonbit-community/MoonJust/actions/runs/31157971210) |
| [PR #22 / PR-061](https://github.com/moonbit-community/MoonJust/pull/22) | `f18a3e269e2c9a260bf5f543d6a0795a7db06ab4` | [31157988228](https://github.com/moonbit-community/MoonJust/actions/runs/31157988228) | [31158135642](https://github.com/moonbit-community/MoonJust/actions/runs/31158135642) |
| [PR #23 / PR-062](https://github.com/moonbit-community/MoonJust/pull/23) | `4420c87fbedfe06354f29632169bcf9ec803e77a` | [31158151375](https://github.com/moonbit-community/MoonJust/actions/runs/31158151375) | [31158330793](https://github.com/moonbit-community/MoonJust/actions/runs/31158330793) |
| [PR #24 / PR-063](https://github.com/moonbit-community/MoonJust/pull/24) | `9546ba0898dfbf636f7ffd14d70f30042d1f7901` | [31158348742](https://github.com/moonbit-community/MoonJust/actions/runs/31158348742) | [31158510455](https://github.com/moonbit-community/MoonJust/actions/runs/31158510455) |
| [PR #25 / PR-064](https://github.com/moonbit-community/MoonJust/pull/25) | `9397a9828b0834c7a2d3c4f072ea5e1b09b6d137` | [31158530290](https://github.com/moonbit-community/MoonJust/actions/runs/31158530290) | [31158848996](https://github.com/moonbit-community/MoonJust/actions/runs/31158848996) |
| [PR #26 / second-audit remediation](https://github.com/moonbit-community/MoonJust/pull/26) | `8e9a3830d5e643c0e209db5a142c27d457932bb9` | [31163416512](https://github.com/moonbit-community/MoonJust/actions/runs/31163416512) | [31163576694](https://github.com/moonbit-community/MoonJust/actions/runs/31163576694) |

Every listed PR run and post-merge run completed Quality gates plus the
Ubuntu, macOS, and Windows native smoke jobs successfully.

## Second-audit verdict

The independent second pass reproduced the command surface against the pinned
`just 1.57.0` binary and found real gaps in query argument rejection, multiple
group membership, option rendering, init path selection, output streams, and
JSON parameter/recipe serialization. PR #26 fixed those gaps, expanded the
byte-for-byte oracle from 12 to 24 Native/Wasm cases, and reran the full gates.

The audit also corrected the upstream ownership map: 86 registrations whose
prerequisites are present are backed by Phase 6 executable anchors, 30 shell
completion registrations are excluded, and five maintenance-only registrations
are not applicable. Cases requiring module graph composition, filesystem search
state, invocation parsing, recipe execution, or terminal styling remain planned
in their owning later phases. No unresolved gap remains inside the declared
Phase 6 scope, so the Phase 6 exit is passed.
