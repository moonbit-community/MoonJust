# Phase 0-5 strict exit audit

- Review date: 2026-08-06
- Reviewed baseline: `origin/main` at
  `b8e6d2c617ee9e941f31837da4e71ff93ff313f7`
- Accepted specification: `docs/PROJECT_PLAN.md` v1.0
- Upstream baseline: `just 1.57.0` at
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Review rule: a passing build is necessary, but a phase passes only when every
  exit has traceable implementation, positive and negative tests, required
  differential evidence, and machine-verified compatibility metadata.

## Verdict

This audit supersedes the 2026-08-05 acceptance claim. Phase 0-5 have now been
re-certified against structured manifests, executable positive/negative tests,
the pinned Rust oracle, target checks, and the Native C-binding sanitizer run.

| Phase | Implementation state | Plan exit | Decision |
| --- | --- | --- | --- |
| 0 | Merged and re-certified | Passed | Pinned source, executable identity and structured 2,417-row map are machine verified |
| 1 | Merged and re-certified | Passed | Five contracts, public interfaces, architecture and Native/wasm1 outlines pass |
| 2 | Merged and re-certified | Passed | All 93 lexer registrations, 21 oracle cases and 100,000-input hardening are linked |
| 3 | Merged and remediated | Passed | Parser/formatter/tangle mapping, semantic formatter proof and CommonMark hardening pass |
| 4 | Merged and remediated | Passed | Real HostFs, canonical identity, source loading and semantic/loading validation pass |
| 5 | Implemented and re-certified | Passed | Scopes, typed 83-builtin registry, explicit effects, Rust oracle and bounded hashes pass |

## Confirmed baseline

- `moon test --target native` passes 109/109 and `moon test --target wasm` passes
  108/108. The Native-only HostFs range test is excluded on wasm because the
  portable `x/fs` adapter explicitly reports missing range capability.
- The exact upstream commit and 2,417 test names are pinned. Every applicable
  Phase 3-5 row is `covered-by`, has Native/wasm1 targets, and points to an
  executable phase manifest plus a verifier-checked `suite`/`test_name` anchor.
  Repeated anchors are explicitly family-level evidence, not independent
  oracle rows.
- Phase 1 exposes five contracts and Phase 2 records 93 lexer registrations,
  21 adapted oracle cases and 100,000 deterministic hardening inputs.
- Architecture checks keep parser/semantic/evaluator core packages independent
  from concrete host adapters.
- The Native C-binding ASan run executes all 109 tests without memory errors or
  leaks. The evaluator and hash tests include adversarial recursion, empty,
  boundary, large-input and capability-denial cases.
- After `moon coverage clean`, `moon test --target native --enable-coverage`
  followed by `moon coverage report -f summary --ignore-missing-files` records
  4,273/6,085 instrumented points (70.2%). This is a
  transparent Phase 0-5 baseline, not a claim that the separate 1.0 release
  threshold of 90% core/80% host coverage has already been met. Native FFI is
  not instrumented and is covered by the real-filesystem test plus ASan run.

## Completed evidence

### Phase 0-2 evidence

1. `test-map.jsonl` has one structured row for every registration and
   `verify_manifest.py` checks IDs, order, owner, targets and evidence.
2. CI builds the official `just 1.57.0` from the pinned source and lockfile;
   `phase5_oracle.py` verifies 20 executable SemVer/regexp outcomes.
3. Structured manifest parsing and exact Native/wasm1 outline checks pass.

### Phase 3

Phase 3 remediation is complete. The generated case manifest covers all 324
applicable parser/formatter/Markdown/tangle registrations, with Native/wasm1
suite evidence, semantic AST equivalence, and zero-through-three-space fence
hardening. Phase 3 is restored to `implemented/passed` in its compatibility
manifest.

### Phase 4

Phase 4 remediation is complete. The HostFs contract has a real `x/fs` adapter
with native `realpath`, search covers `justfile`/`.justfile` case variants and
ceilings, source loading is unified across filesystem/stdin/Markdown paths, and
the graph records canonical identities and span-bearing cycle chains. Semantic
tests cover minimum-version, false `no-cd`, dependency arity, recipe variable
references and static cycles. Phase 4 is restored to `implemented/passed`.

### Phase 5

Phase 5 remediation is complete. `LazyEnvironment` records explicit lazy states,
DFS depth and name-only cycle stacks; recipe/module scopes implement defaults,
distinct `+`/`*` variadics, shadowing and exports. The 83-row typed registry is
checked against `phase-5-builtins.jsonl`; context/effect calls remove every
former placeholder. Context facts keep native invocation/executable paths and
local timezone input explicit. Regexp replacement and SemVer behavior are
checked by the pinned Rust oracle.
SHA-256 and BLAKE3 use incremental state, and Native file hashing pulls bounded
ranges through `HostFs::stream_file`; the portable adapter reports unavailable
range capability instead of buffering whole files.

## Status policy

`compat/phase-3.toml` through `compat/phase-5.toml` are `implemented/passed`.
No applicable Phase 0-5 Tier A test remains `unsupported`, `blocked-platform`,
`unverified` or without executable evidence. The Phase 5 PR and its post-merge
`main` CI are green, so this audit is published against the merged `main`
baseline.

## Publication verification

- Phase 5 implementation PR: [#13](https://github.com/moonbit-community/MoonJust/pull/13), squash-merged as
  `cee01fd202ec4a60c6cb8815f1af5b9cce953294`.
- Required Phase 5 PR CI: [run 31101620775](https://github.com/moonbit-community/MoonJust/actions/runs/31101620775) passed all quality, Ubuntu, macOS and Windows jobs.
- Required post-merge `main` CI: [run 31101791384](https://github.com/moonbit-community/MoonJust/actions/runs/31101791384) passed all required jobs for the reviewed baseline.
- Audit-remediation PR: [#15](https://github.com/moonbit-community/MoonJust/pull/15), squash-merged as
  `b8e6d2c617ee9e941f31837da4e71ff93ff313f7`.
- Required audit-remediation PR CI: [run 31107368869](https://github.com/moonbit-community/MoonJust/actions/runs/31107368869) passed all quality, Ubuntu, macOS and Windows jobs.
- Required post-merge `main` CI for the reviewed baseline: [run 31107621334](https://github.com/moonbit-community/MoonJust/actions/runs/31107621334) passed all required jobs.
