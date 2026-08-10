# Phase 8 Completion Report

- Status: implemented; local exit passed
- Date: 2026-08-10
- Release identity: `0.5.0-alpha`
- Upstream baseline: `just 1.57.0`
- Required targets: Native and wasm1
- Remote PR/CI evidence: passed on PR #37

Phase 8 delivers the sequential executor preview. Application planning validates
the complete recipe graph and composes explicit shell, cwd, environment, dotenv,
stdio, script, and process contracts before the runtime grants process access.

## Delivery Matrix

| PR | Contract | Local evidence |
| --- | --- | --- |
| PR-080 | `CommandSpec`, `ProcessResult`, typed exit/signal failures | `src/host/contracts.mbt`, `src/host_process`, FakeHost assertions |
| PR-081 | ordered ordinary lines, sigils, echo/quiet, ignored failures, dry-run | `src/executor/line.mbt`, line oracle fixture |
| PR-082 | scripts, shebang/interpreter, extension/BOM, executable mode, cleanup | `src/executor/script.mbt`, native and wasm script smoke |
| PR-083 | async backticks/shell capture, exact newline trim, stderr and failure propagation | `src/evaluator/async_evaluator.mbt`, executor effect tests |
| PR-084 | deterministic dependency order, once key, starred/parameterized dependencies | `src/executor/plan.mbt`, DAG tests and order fixture |
| PR-085 | stream separation, verbosity, timestamp/color, elapsed timing, stable failures | `src/executor/output.mbt`, native CLI output smoke |
| PR-086 | async cancellation boundary, signal mapping, cancellation-safe cleanup | `src/runtime/runtime.mbt`, native signal test |
| PR-087 | native/wasm process adapters, exact cwd/env/stdio, policy diagnostics | `src/host_process`, `policies/execute.toml`, moonrun smoke |

## Verification

- `moon fmt && moon info`: pass; generated interfaces refreshed.
- `./tools/check_architecture.sh`: pass; core packages remain free of async/FFI
  and host leaves contain target-specific effects.
- `moon check --target all --warn-list +73 --deny-warn`: pass with zero warnings.
- `moon test --target native`: 236 passed, 0 failed.
- `moon test --target wasm`: 232 passed, 0 failed.
- `tools/check_phase8_executor.sh`: oracle dry-run, native/wasm CLI corpus and
  executor package tests pass locally.
- Native CLI smoke covers dotenv, effect ordering, failure output,
  timestamp/color, elapsed timing and ordinary dry-run. Wasm execute policy
  covers script creation and process execution; inspect policy rejects writes
  and process execution with a typed capability diagnostic.

## Security and scope

The focused review is recorded in [`PHASE_8_SECURITY_AUDIT.md`](PHASE_8_SECURITY_AUDIT.md).
Temporary scripts are exclusively created, minimally permissioned, and cleaned
under cancellation protection. Command diagnostics redact values and preserve
separate output streams. Parallel scheduling, persistent cache, interactive
terminal streaming, full Windows job-object parity, and browser/wasm-gc process
execution remain explicitly deferred to later phases.

## Publication Evidence

The consolidated Phase 8 delivery is commit `53e7d1a` on
[PR #37](https://github.com/moonbit-community/MoonJust/pull/37), with the
initial PR-080 IR commit `1a34276` retained in history. Remote CI run
[31393683064](https://github.com/moonbit-community/MoonJust/actions/runs/31393683064)
passed Quality gates plus Ubuntu, macOS, and Windows Native smoke jobs.

## Strict Second-Review Verdict

The post-CI second pass rechecked all PR-080 through PR-087 contracts against
the project plan, reran the aggregate gate and target matrix, inspected the
remote commit/CI status, and exercised the policy-denial and dry-run paths.
No unresolved gap remains inside the declared Phase 8 sequential-execution
boundary. Deferred parallel/cache/interactive/full-platform work remains
explicitly assigned to later phases.
