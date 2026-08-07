# Phase 5 completion report

- Status: Implemented; Phase 5 exit passed
- Strict review: 2026-08-07 ([Phase 0-5 audit](PHASE_0_5_AUDIT.md))
- Reviewed implementation and evidence baseline: `main` at `dfaf5b9ec4a0b05f8b2b8094213087c3b2e74313`
- Upstream baseline: `just 1.57.0` at `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Required implementation targets: Native and wasm1
- Scope: runtime values, pure/effectful expression evaluation, typed builtins,
  cryptographic hashes, host capability calls, and evaluator hardening

The remediation is complete. Phase 5 now has executable scope state, complete
typed builtin metadata, explicit context/effect boundaries, Rust oracle cases,
and bounded Native file hashing. wasm1 uses the same evaluator and hash logic;
the portable `NativeFs` adapter reports unavailable range capability rather than
silently buffering an entire file.

## Delivered contracts

| Unit | Implementation | Evidence |
| --- | --- | --- |
| PR-050 | `src/value`, `src/evaluator/evaluator.mbt` | typed string/list/bool values, lazy conditionals, concatenation and short-circuit tests |
| PR-051 | `src/evaluator/lazy.mbt`, `scope.mbt`, `environment.mbt` | `Unevaluated/Evaluating/Evaluated` states, reachable-dependency resolution, undefined/cycle separation, redacted cycle chain, recipe defaults, distinct `+`/`*` variadics, exports and module scope |
| PR-052 | `src/builtin/builtin.mbt` | 83 canonical typed entries with exact arity, aliases, purity, capabilities, targets and evidence |
| PR-053 | regexp adapter and SemVer matcher | global capture replacement, zero-length safety, prerelease/build metadata, partial comparators, default caret and comma requirement behavior |
| PR-054 | `src/builtin/hash.mbt` | SHA-256 context, bounded BLAKE3 subtree stack, randomized boundary and 1 MiB one-shot differential |
| PR-055/056 | `src/evaluator/context.mbt`, `effect.mbt` | explicit native/executable/timezone facts, fs/env/clock/random/process/platform/terminal effects, full ANSI style tokens, PATH/which/require and typed capability failures |
| PR-057 | `src/evaluator/error.mbt` and evaluator limits | recursion/node/output budgets, structured spans, redacted evaluation stack and typed missing-context/argument errors |

## Compatibility and evidence boundary

- `src/builtin.names()` and `registry()` expose the canonical 83-name inventory.
- `tests/upstream/just-1.57.0/phase-5-builtins.jsonl` has one machine-checked row
  per builtin (`min_arguments`, `max_arguments`, aliases, purity, capabilities,
  Native/wasm1 targets, evidence and tracking ID).
- `tests/upstream/just-1.57.0/phase-5-oracle.jsonl` contains 20 pinned Rust
  SemVer/regexp outcomes; `tools/upstream/phase5_oracle.py` executes them against
  the built `just 1.57.0` oracle.
- Effect dispatch accepts a caller-supplied aggregate host; each builtin branch
  calls only the operations declared in its typed capability list. Missing facts
  are `EvaluationError::MissingContext`; denied
  and unavailable host capabilities remain typed `EvaluationError::Host` values.
- Native file hashes call `HostFs::stream_file` and `read_file_range`; the C
  adapter uses `stat` plus bounded `fseek/fread` buffers and is ASan validated.

## Verification evidence

- `moon check --target all --warn-list +73`: pass, no warnings.
- `moon test --target native`: **109 passed, 0 failed**.
- `moon test --target wasm`: **108 passed, 0 failed** (portable NativeFs range
  test is intentionally Native-only; FakeHost covers wasm1 semantics).
- `tools/check_architecture.sh`: fourteen core packages and one host adapter leaf.
- `tools/upstream/verify_snapshot.sh`: 2,417 registrations, structured maps and
  typed builtin manifest verified.
- `tools/upstream/phase5_oracle.py`: 20/20 pinned Rust oracle cases passed.
- `python3 .../moonbit-c-binding/scripts/run-asan.py --repo-root ... --pkg
  src/host_native/moon.pkg`: 109 Native tests passed with no ASan or leak error.
- Native coverage snapshot: evaluator 579/994, builtin 616/926, value 36/55,
  Host contracts/fake 156/183. These numbers are recorded evidence, not a claim
  that the later 1.0 release-coverage threshold is complete; Native FFI is
  validated by its black-box test and ASan because it is not instrumented.
- After `moon coverage clean`, the reproducible total is 4,273/6,085 (70.2%);
  the current builtin package is 616/926. The per-package values above are
  retained only where they match this clean run; the total and builtin values
  supersede the earlier pre-clean snapshot.
- Every Phase 5 case row carries an executable `suite`/`test_name` anchor that
  the manifest verifier resolves to a declared MoonBit test. Repeated anchors
  explicitly denote family-level coverage rather than independent oracle rows.
- `moon info` regenerated and reviewed all changed `.mbti` interfaces.

## Publication evidence

- Implementation PR: [#13](https://github.com/moonbit-community/MoonJust/pull/13), squash-merged at
  `cee01fd202ec4a60c6cb8815f1af5b9cce953294`.
- PR CI: [run 31101620775](https://github.com/moonbit-community/MoonJust/actions/runs/31101620775) passed all required jobs.
- Post-merge `main` CI for the Phase 5 implementation baseline: [run 31101791384](https://github.com/moonbit-community/MoonJust/actions/runs/31101791384) passed all required jobs.
- Audit-remediation PR: [#15](https://github.com/moonbit-community/MoonJust/pull/15), squash-merged at
  `b8e6d2c617ee9e941f31837da4e71ff93ff313f7`.
- Audit-remediation PR CI: [run 31107368869](https://github.com/moonbit-community/MoonJust/actions/runs/31107368869) passed all required jobs.
- Post-merge `main` CI for the published baseline: [run 31107621334](https://github.com/moonbit-community/MoonJust/actions/runs/31107621334) passed all required jobs.
- Baseline synchronization PR: [#16](https://github.com/moonbit-community/MoonJust/pull/16), squash-merged at
  `07356b69c2d6aeeea2babf7dd3ea524ecce08f84`.
- Baseline synchronization PR CI: [run 31115918942](https://github.com/moonbit-community/MoonJust/actions/runs/31115918942) passed all required jobs.
- Post-merge `main` CI after baseline synchronization: [run 31116224835](https://github.com/moonbit-community/MoonJust/actions/runs/31116224835) passed all required jobs.
- Final evidence-label PR: [#17](https://github.com/moonbit-community/MoonJust/pull/17), squash-merged at
  `dfaf5b9ec4a0b05f8b2b8094213087c3b2e74313`.
- Final evidence-label PR CI: [run 31116718745](https://github.com/moonbit-community/MoonJust/actions/runs/31116718745) passed on the third attempt after transient Actions setup failures.
- Post-merge `main` CI for the final published baseline: [run 31119139899](https://github.com/moonbit-community/MoonJust/actions/runs/31119139899) passed on the third attempt after transient Actions setup failures.

## Temporary external CI incident

The 2026-08-07 GitHub Actions major outage prevented five consecutive PR #18
trigger attempts from completing Ubuntu/macOS platform smoke. The exact run
IDs and the temporary job-level skip, with its restoration condition, are
recorded in [`PHASE_0_5_AUDIT.md`](PHASE_0_5_AUDIT.md). This does not change the
Phase 5 implementation verdict or claim a platform pass that was not observed.
GitHub reported Actions operational again on 2026-08-07, so the full
Ubuntu/macOS/Windows matrix has been restored. The exception remains open until
the restoration PR and its post-merge `main` run complete all four checks; the
closure evidence is tracked in [`PHASE_0_5_AUDIT.md`](PHASE_0_5_AUDIT.md).
