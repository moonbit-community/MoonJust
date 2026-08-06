# Phase 0-5 strict exit audit

- Review date: 2026-08-06
- Reviewed baseline: `origin/main` at `b5e8ed7`
- Accepted specification: `docs/PROJECT_PLAN.md` v1.0
- Upstream baseline: `just 1.57.0` at
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Review rule: a passing build is necessary, but a phase passes only when every
  exit has traceable implementation, positive and negative tests, required
  differential evidence, and machine-verified compatibility metadata.

## Verdict

This audit supersedes the 2026-08-05 acceptance claim. Phase 0-2 remain
accepted at their original boundaries and will be re-certified against the new
evidence map. Phase 3-5 have merged implementation baselines, but their exits
are remediation/pending until the gaps below are closed.

| Phase | Implementation state | Plan exit | Decision |
| --- | --- | --- | --- |
| 0 | Merged | Passed | Rebuild the pinned-source oracle and per-test map; retain only reproducible evidence |
| 1 | Merged | Passed | Re-run contracts, public API, architecture and coverage gates against the repaired baseline |
| 2 | Merged | Passed | Re-link all 93 lexer registrations to executable evidence and retain 100,000-input hardening |
| 3 | Merged baseline | Pending | Full parser/formatter/tangle mapping and semantic formatter proof are missing |
| 4 | Merged baseline | Pending | Real filesystem, canonical identity and complete semantic/loading validation are missing |
| 5 | Merged baseline | Pending | Evaluator scopes, typed builtin evidence, real effects and streaming hashes are incomplete |

## Confirmed baseline

- `main` builds for all configured MoonBit targets and its current Native and
  wasm1 suites pass. This proves the checked implementation only; it does not
  prove the original Phase 3-5 exits.
- The exact upstream commit and 2,417 test names are pinned, but the old
  names-only inventory did not classify each test or link it to evidence.
- Phase 1 exposes five contracts and Phase 2 records 93 lexer registrations,
  21 adapted oracle cases and 100,000 deterministic hardening inputs.
- Architecture checks keep parser/semantic/evaluator core packages independent
  from concrete host adapters.

## Required remediation

### Phase 0-2 evidence

1. Generate one structured row for every upstream registration with owner
   phase, tier, targets, disposition, evidence and tracking owner.
2. Build official `just 1.57.0` from the exact source commit and `Cargo.lock` in
   CI; record source, executable and version identity.
3. Replace hand-written count greps with structured manifest parsing and exact
   test-outline checks, then re-run Phase 1-2 API, architecture and coverage.

### Phase 3

1. Execute every applicable parser, formatter, Markdown and tangle registration
   as a ported, parameterized or differential case.
2. Require formatter idempotence and equality of the parsed semantic model
   before and after formatting.
3. Implement CommonMark fenced blocks with zero through three leading spaces,
   preserve original lines/bytes, and retain deterministic resource budgets.

### Phase 4

1. Implement a real HostFs adapter and differential search for `justfile` and
   `.justfile`, including case-insensitive matches, ceilings and explicit paths.
2. Use canonical filesystem identity for imports/modules, including symlink
   aliases, optional/fallback behavior and span-bearing cycle chains.
3. Unify explicit, search, stdin, global, Markdown, import and module sources;
   complete setting/attribute conflict and dependency-arity validation.

### Phase 5

1. Implement recipe parameters, module/export scopes, true lazy states,
   recursion detection and a redacted evaluation stack.
2. Replace the names-only builtin list with 83 typed entries covering arity,
   aliases, purity, capability, targets and executable evidence.
3. Remove placeholder host results; use `EvaluationContext` and explicit
   fs/env/clock/random/process facts on every supported target.
4. Match Rust regexp replacement and SemVer requirement behavior; make
   SHA-256/BLAKE3 file hashing genuinely incremental and bounded-memory.

## Status policy

`compat/phase-3.toml` through `compat/phase-5.toml` remain
`remediation/pending`. A phase may return to `implemented/passed` only in the PR
that closes every listed exit, updates its report and passes required PR CI and
post-merge `main` CI. No applicable Phase 0-5 Tier A test may remain
`unsupported`, `blocked-platform`, `unverified` or without executable evidence.
