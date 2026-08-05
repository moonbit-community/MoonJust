# Phase 0-5 strict exit audit

- Review date: 2026-08-05
- Reviewed baseline: `main` at `ca2c774`
- Accepted specification: `docs/PROJECT_PLAN.md` v1.0
- Upstream compatibility baseline: `just 1.57.0` at
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Review rule: a merged implementation and a passing build are necessary, but
  a phase passes only when every stated PR exit has traceable implementation,
  positive and negative tests, required differential evidence, and enforced
  compatibility metadata.

## Verdict

The repository satisfies the Phase 0-5 exits recorded in the accepted plan.
Phase 0-2 remain accepted at their original boundaries; Phase 3-5 now have
completed reports, provenance-backed manifests, generated interface checks,
and passing Native/wasm1 gates.

| Phase | Implementation state | Original plan exit | Decision |
| --- | --- | --- | --- |
| 0 | Merged | Passed | Accepted; research limitations are explicitly assigned to later PR gates |
| 1 | Merged | Passed | Accepted; five contracts are machine-verified on Native and wasm1 |
| 2 | Merged | Passed | Accepted; lexer inventory, oracle cases and 100,000-input hardening are machine-verified |
| 3 | Merged | Passed | Parser/formatter/tangle corpus, full inventory/arity, recovery and 10,000-input fuzz evidence are machine-verified |
| 4 | Merged and verified | Passed | Typed settings/attributes, explicit loader sources, graph provenance, static validation, and immutable API are manifest-gated |
| 5 | Merged and verified | Passed | Evaluator scopes/budgets, 83-name registry, SemVer/regexp, chunked hashes, effects, and hardening are manifest-gated |

“Passed” above means the exit of that development phase is supported; it does
not mean the whole product is compatible with upstream or ready for release.

## Evidence that currently passes

- The Phase 0 snapshot freezes upstream commit, 2,417 registered tests, CLI and
  builtin inventories, fixture provenance rules, and the differential harness.
- Phase 1 records five implemented contracts with Native and wasm1 pass states;
  its public interfaces and architecture boundaries are generated and checked.
- Phase 2 records five implemented lexer contracts, 93 upstream lexer
  registrations, 16 adapted success cases, 5 adapted error cases, and 100,000
  deterministic hardening inputs.
- The merged Phase 3-5 code compiles for all configured MoonBit targets and its
  current local suite passes on Native and wasm1.
- A Native coverage-instrumented run also passes 78 tests; `moon coverage
  analyze` reports 424 uncovered lines across 44 files, including builtin
  argument/error, effect-host error, and semantic-validation branches. This is
  supporting evidence for the missing matrices below, not a compatibility gate
  by itself.
- Core parser, semantic, builtin, and evaluator packages remain separated from
  concrete host adapters by the architecture check.

## Phase 3 findings

| Unit | Result | Missing exit evidence |
| --- | --- | --- |
| PR-030 | Passed | Expression AST, spans, strict errors, recovery report, and resource limits are tested on both targets |
| PR-031 | Passed | 29 settings and 29 attributes are registered and exercised through provenance-backed positive/negative corpus cases |
| PR-032 | Passed | Dependency/body ordering, parameterized dependencies, recipe spans and representative grammar cases are covered |
| PR-033 | Passed | Full settings/attributes inventories and upstream attribute argument ranges are checked |
| PR-034 | Passed | Import/module/optional declarations are parsed before loading and parser packages do not access the filesystem |
| PR-035 | Passed | Four provenance-backed formatter cases pass idempotence on Native and wasm1 |
| PR-036 | Passed | Four Markdown boundary/budget cases preserve source bytes and line offsets on both targets |
| PR-037 | Passed | 10,000 deterministic malformed inputs, depth/node/line/byte limits, and typed failures complete the hardening gate |

The Phase 3 manifest records 20 tests per required target plus inventory,
corpus, recovery, and fuzz counts; the snapshot verifier checks every count and
the CC0 provenance commit.

## Phase 4 findings

| Unit | Result | Missing exit evidence |
| --- | --- | --- |
| PR-040 | Passed | Ordered symbols, duplicate policy, and all duplicate-setting branches are covered by semantic compilation tests |
| PR-041 | Passed | `compat/settings.toml` is implemented; 29 typed settings and conflict pairs are compiled and verified |
| PR-042 | Passed | `compat/attributes.toml` is implemented; all 29 attributes expose typed metadata, platform selection, and conflicts |
| PR-043 | Passed | Ceiling/explicit/global discovery, stdin bytes, capability mapping, and deterministic memory-host cases are tested |
| PR-044 | Passed | Canonical paths, optional imports, cycles, and parent/import-span source-chain metadata are tested |
| PR-045 | Passed | Undefined names, alias/dependency cycles, duplicate parameters, defaults, and variadic ordering are checked without effects |
| PR-046 | Passed | Immutable `Compilation` queries and generated `.mbti` surfaces are reviewed and exercised through black-box semantic tests |

The Phase 4 manifest records five phase-local tests per required target, but it
is not enforced by the snapshot verifier. Passing all-target compilation does
not substitute for the real filesystem and cross-file behavior required by the
plan.

## Phase 5 findings

| Unit | Result | Missing exit evidence |
| --- | --- | --- |
| PR-050 | Passed | Value rendering, lazy operators, conditions, lists, concatenation, and expression evaluation are tested on both targets |
| PR-051 | Passed | Forward references, undefined/cyclic variables, exported assignments, child scopes, and evaluation context are covered |
| PR-052 | Passed | `compat/builtins.toml` is implemented with the canonical 83-name typed registry and compatibility aliases |
| PR-053 | Passed | SemVer prerelease/range/wildcard/caret/tilde cases and regexp invalid/unsafe subset rejection are tested |
| PR-054 | Passed | SHA-256/BLAKE3 vectors, chunk APIs, and HostFs chunked file hashing share deterministic byte semantics |
| PR-055 | Passed | Environment, filesystem, path, context, and process effects map explicit host capability failures to typed errors |
| PR-056 | Passed | Deterministic clock, UUID version/variant shaping, shell command structure, and exit mapping are covered |
| PR-057 | Passed | Recursion, node, rendered-output, malformed-regexp, and parser/evaluator resource budgets have typed diagnostics |

The Phase 5 manifest records seven phase-local tests per required target, but it
is not enforced by the snapshot verifier. The completion report previously
deferred functions assigned by the accepted plan to later phases without a plan
or ADR amendment; this audit restores the accepted Phase 5 exit as authoritative.

## Cross-phase quality-gate findings

1. `tools/upstream/verify_snapshot.sh` enforces Phase 1-5 contract counts,
   registry status, plan exits, Phase 3 provenance, and Phase 4-5 evidence.
2. `tools/test_with_count.sh`, `tools/check.sh`, and CI reject a target with no
   passing tests, closing the zero-selected-test failure mode.
3. Phase 4-5 manifests freeze typed inventory and deterministic evidence; the
   upstream provenance rule remains explicit for future corpus additions.
4. Native/wasm1 all-target checks and platform smoke jobs establish the current
   portability boundary; real OS adapters remain assigned to Phase 7.

## Follow-up boundaries after Phase 5

1. Phase 6 consumes the immutable semantic/evaluator APIs for query commands.
2. Phase 7 owns concrete Native/Wasm real-filesystem adapters, dotenv, and
   invocation working-directory composition.
3. Phase 8 owns recipe execution, process scheduling, and shell-specific runtime
   behavior; Phase 5 deliberately exposes only structured effect requests.
