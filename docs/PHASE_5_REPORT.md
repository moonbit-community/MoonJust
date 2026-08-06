# Phase 5 completion report

- Status: Implemented; Phase 5 exit passed
- Strict review: 2026-08-06 ([Phase 0-5 audit](PHASE_0_5_AUDIT.md))
- Published baseline: `main` at `cee01fd202ec4a60c6cb8815f1af5b9cce953294`
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
- Native coverage snapshot: evaluator 579/994, builtin 733/1,057, value 36/55,
  Host contracts/fake 156/183. These numbers are recorded evidence, not a claim
  that the later 1.0 release-coverage threshold is complete; Native FFI is
  validated by its black-box test and ASan because it is not instrumented.
- `moon info` regenerated and reviewed all changed `.mbti` interfaces.

## Publication evidence

- Implementation PR: [#13](https://github.com/moonbit-community/MoonJust/pull/13), squash-merged at
  `cee01fd202ec4a60c6cb8815f1af5b9cce953294`.
- PR CI: [run 31101620775](https://github.com/moonbit-community/MoonJust/actions/runs/31101620775) passed all required jobs.
- Post-merge `main` CI: [run 31101791384](https://github.com/moonbit-community/MoonJust/actions/runs/31101791384) passed all required jobs.
