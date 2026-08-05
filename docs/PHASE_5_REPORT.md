# Phase 5 completion report

- Status: Complete
- Upstream baseline: `just 1.57.0`
- Required implementation targets: Native and wasm1
- Scope: runtime values, pure/effectful expression evaluation, typed builtins,
  cryptographic hashes, host capability calls, and evaluator hardening

## Delivered contracts

| Unit | Implementation | Evidence |
| --- | --- | --- |
| PR-050 | `src/value` and pure `src/evaluator` | string/list/bool values, conditionals, concatenation and short-circuit tests |
| PR-051 | immutable compilation environment evaluation | forward references, undefined names and variable-cycle tests |
| PR-052 | typed string/list/path builtin dispatch | arity/type errors, replacement, quoting and path table tests |
| PR-053 | `moonbitlang/regexp@0.3.5` adapter and SemVer matcher | anchored/class matching, invalid pattern mapping and comparison tests |
| PR-054 | SHA-256 adapter and pure MoonBit BLAKE3 | empty, `abc`, cross-chunk, and file-host hash vectors |
| PR-055 | explicit `EffectEvaluator` host calls | fake HostFs/HostEnv, path and capability error behavior |
| PR-056 | clock, UUID and shell calls | deterministic clock/random/process contracts and exit mapping |
| PR-057 | evaluator budgets and diagnostics | recursion, node, output and UTF-8 limits with structured spans |

## Frozen decisions

- `src/value`, `src/evaluator`, and the pure portion of `src/builtin` never read
  process-global state or import a concrete host adapter.
- Effectful builtins are reachable only through `call_effect` and a caller
  supplied value implementing all required host capability traits. Missing or
  denied capabilities remain typed `EvaluationError::Host` values.
- SHA-256 uses the exact official dependency `moonbitlang/x@0.4.47`, isolated
  to the builtin package. BLAKE3 is a self-contained specification port because
  no approved cross-target MoonBit package met the plan's contract.
- The regexp adapter is exact-version `moonbitlang/regexp@0.3.5`; compilation
  failures are mapped to a stable typed requirement error. The package is not
  exposed through the root facade.
- File hashes read bytes through `HostFs`; they do not bypass the capability
  boundary or silently fall back to an ambient filesystem.

## Compatibility boundary

Phase 5 establishes the evaluator and the stable typed builtin registry. The
full upstream list of 83 just functions is intentionally delivered across the
later file, context, CLI, and execution phases in `PROJECT_PLAN.md`; no name is
silently accepted before its contract exists. `src/builtin.names()` therefore
lists only pure functions implemented in this phase, while effectful names are
dispatched by `EffectEvaluator`.

## Exit evidence

- `moon check --target all --warn-list +73` passes without warnings.
- `moon test --target native`: 78 passed, 0 failed.
- `moon test --target wasm`: 78 passed, 0 failed.
- `tools/check_architecture.sh` covers all fourteen Phase 1-5 packages and
  verifies that value/builtin/evaluator core code has no target-specific FFI.
- Generated `.mbti` files were refreshed with `moon info` and reviewed for the
  public value, builtin, evaluator, and root facade surfaces.
