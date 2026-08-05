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

The repository does not yet perfectly satisfy Phase 0-5. Phase 0-2 meet their
phase-specific exits, including the documented hand-off boundaries. Phase 3-5
have useful, compiling implementation baselines, but do not meet all exits in
the accepted plan and therefore remain pending phase acceptance.

| Phase | Implementation state | Original plan exit | Decision |
| --- | --- | --- | --- |
| 0 | Merged | Passed | Accepted; research limitations are explicitly assigned to later PR gates |
| 1 | Merged | Passed | Accepted; five contracts are machine-verified on Native and wasm1 |
| 2 | Merged | Passed | Accepted; lexer inventory, oracle cases and 100,000-input hardening are machine-verified |
| 3 | Merged | Passed | Parser/formatter/tangle corpus, full inventory/arity, recovery and 10,000-input fuzz evidence are machine-verified |
| 4 | Baseline merged | Pending | Full typed settings/attributes, loader matrix, graph diagnostics, and static validation are incomplete |
| 5 | Baseline merged | Pending | Evaluator corpus/scope, full builtin inventory, adapters, streaming hashes, effects, and hardening are incomplete |

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
| PR-040 | Partial | Ordered symbols and basic duplicates exist; the complete allow-duplicate setting behavior matrix is absent |
| PR-041 | Not passed | `compat/settings.toml` remains `planned`; settings are held in a string-keyed table and only selected conflicts are compiled |
| PR-042 | Not passed | `compat/attributes.toml` remains `planned`; only a subset receives compiled metadata and conflict semantics |
| PR-043 | Not passed | Search/explicit loading use a fake memory host; stdin/global discovery and memory-vs-real-filesystem differential tests are absent |
| PR-044 | Partial | Optional imports and a cycle are tested; fallback resolution and complete cross-file span/source-chain diagnostics are absent |
| PR-045 | Partial | Basic missing names and cycles are checked; the complete recipe parameter and static-error matrix is absent |
| PR-046 | Partial | The immutable `Compilation` facade and `.mbti` exist; dedicated black-box API documentation tests are absent |

The Phase 4 manifest records five phase-local tests per required target, but it
is not enforced by the snapshot verifier. Passing all-target compilation does
not substitute for the real filesystem and cross-file behavior required by the
plan.

## Phase 5 findings

| Unit | Result | Missing exit evidence |
| --- | --- | --- |
| PR-050 | Partial | Core value/expression cases pass locally; the required upstream expression corpus is not registered or run |
| PR-051 | Not passed | Forward references/undefined/cycles exist, but recipe parameters, exports, module scopes, shadowing and lazy-scope tests are incomplete |
| PR-052 | Not passed | The pure dispatch exposes a small subset while `compat/builtins.toml` keeps all 83 canonical functions `planned`; names and metadata are not a complete typed table |
| PR-053 | Not passed | Regexp and a small dotted-version comparator exist, but upstream Rust differential corpora, full SemVer requirement semantics, unsafe regexp subset checks, and malicious-complexity cases are absent |
| PR-054 | Partial | SHA-256/BLAKE3 known vectors pass; file hashing reads a complete file through `HostFs`, with no streaming API or randomized chunk differential |
| PR-055 | Not passed | Selected environment/filesystem effects use fake capabilities; the complete environment/filesystem/context function and error/path differential matrix is absent |
| PR-056 | Partial | Fake clock/random/process tests exist; full clock/UUID/shell contract coverage and platform execution matrix are absent |
| PR-057 | Partial | A recursion limit is exercised; node/output budgets, error stacks, uncontrolled-recursion cases, and sensitive-environment leakage checks are incomplete |

The Phase 5 manifest records seven phase-local tests per required target, but it
is not enforced by the snapshot verifier. The completion report previously
deferred functions assigned by the accepted plan to later phases without a plan
or ADR amendment; this audit restores the accepted Phase 5 exit as authoritative.

## Cross-phase quality-gate findings

1. `tools/upstream/verify_snapshot.sh` enforces Phase 1, Phase 2, and Phase 3
   contract counts, corpus provenance, and plan exit state; Phase 4-5 remain.
2. `tools/check.sh` and CI run Native and wasm tests, but do not assert the
   selected test count. This leaves the zero-selected-test failure mode named in
   section 12.6 of the plan unguarded.
3. Phase 4-5 manifests still need upstream fixture registration/provenance
   counts before their local tests can establish the required differential
   compatibility.
4. The latest merged multi-platform smoke and local quality gate establish
   portability of the current baseline, not completeness of the plan exits.

## Required closure before Phase 6 acceptance

1. Implement and test every Phase 4 setting and non-runtime attribute contract,
   real-filesystem/stdin/global discovery, fallback graph behavior, cross-file
   diagnostics, and the full static-validation matrix.
2. Implement the Phase 5 scope model and all Phase 5-owned pure/effectful
   functions from the 83-name inventory, with typed metadata and differential
   tests.
3. Replace the limited SemVer behavior with the frozen requirement contract;
   validate/translate/reject regexp behavior against the accepted subset and add
   adversarial complexity tests.
4. Add incremental SHA-256/BLAKE3 file hashing and randomized chunk
   differential tests, plus the missing evaluator budget/error-stack/security
   matrix.
5. Extend the snapshot verifier to enforce Phase 4-5 evidence and make local/CI
   test commands assert non-zero expected test counts.
6. Only after all rows above pass should `plan_exit` change from `pending` to
   `passed` and the Phase 3-5 reports be renamed as completion reports.
