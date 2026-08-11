# Phase 9 Completion Report

- Scope: PR-090 through PR-094 from `docs/PROJECT_PLAN.md`
- Compatibility baseline: `just 1.57.0` at `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Release identity: `0.6.0-alpha`
- Local review date: 2026-08-11
- Remote protected-main evidence: pending PR merge and post-merge CI

## Delivered contracts

| PR | Contract | Exit evidence |
| --- | --- | --- |
| PR-090 | bounded scheduler, `--jobs`, `[parallel]`, serial fences, stable fairness and deterministic failure selection | scheduler model, Native/Wasm runtime peak/order/failure tests |
| PR-091 | versioned length-delimited cache key, evaluated `extra`/inputs/outputs, incremental BLAKE3 and strict manifest | pure cache invalidation, round-trip and adversarial tests |
| PR-092 | permanent per-digest lock, atomic `0600`/Full-sync entry, corruption and stale-temporary recovery, selective `--clean` | Native/Wasm store tests and two-process contention gate |
| PR-093 | bounded hashing, streamed process pipes, 16 MiB per-stream capture budget, cancellation-safe process/script/lease cleanup | exact/overflow boundary, cancellation and missing-output non-publication tests |
| PR-094 | fixed-seed randomized DAG and concurrency determinism | 1,000 generated schedules, stable output/failure tests, Phase 9 gate |

The async planner now emits an explicit recipe-task DAG. Ordinary dependency
groups chain terminal tasks; `[parallel]` groups share their entry fence and
join before the recipe body. Subsequent dependencies use the same rule after
the recipe task. A FIFO semaphore bounds all runnable work, while stdout,
stderr and the selected failure are merged by stable task order rather than
completion timing.

## Cache and security review

ADR-008 fixes MoonJust's project-owned `.moonjust-cache/v1` format. Keys include
the evaluated script, executor, exported environment, working directory,
positional values, `extra`, sorted input digests and output contract. Input
hashing uses 64 KiB HostFs ranges and a bounded incremental BLAKE3 state.

Manifests are untrusted. Parsing rejects unsupported versions and algorithms,
wrong digests, wrong recipes, duplicate outputs, absolute paths, drive paths,
backslashes, traversal, control characters, oversized documents and excess
inputs or outputs. Host adapters read no more than 256 KiB plus one sentinel
byte, so a hostile file cannot force an unbounded manifest allocation.
Corrupt/truncated entries are misses and are replaced only after a successful
run whose declared outputs exist.

Native and wasm1 stores keep permanent sibling lock files and hold OS-exclusive
locks across lookup, execution and commit. Successful manifests use an
exclusively created same-directory temporary file, mode `0600`, Full sync and
atomic rename. Cancellation releases the child process, temporary script and
cache lease. A later lease removes strictly recognized stale commit
temporaries under the same digest lock while preserving lookalike files.
Lease tokens are bound to the exact directory and digest, and
structural `Debug` output redacts bodies, arguments and environment values.
`--no-cache` and dry-run perform no cache lock or publication.

Process stdout and stderr are drained concurrently in chunks rather than by an
unbounded whole-process collector. Captured streams are limited to 16 MiB each;
crossing the limit cancels the child and returns a deterministic typed host
error. Discarded streams are drained without retention, so child pipe pressure
cannot turn into executor memory growth.

## Compatibility accounting

The pinned 2,417-row upstream inventory assigns 74 registrations to Phase 9:
72 map to executable Native/wasm1 family evidence in
`tests/upstream/just-1.57.0/phase-9-cases.jsonl`, and two are explicitly
`unsupported` storage-tree observations. Failed recipes never publish the
upstream empty placeholder entry, while `--clean` preserves permanent lock
files and the versioned cache directory. Removing those locks would
reintroduce an unlink/recreate split-lock race. Both differences name their
reason and `PROJECT_PLAN_PR-105` tracking in the machine map; Phase 10 owns
their final compatibility resolution.

## Gates

`tools/check_phase9_runtime.sh` runs the focused scheduler, cache, runtime,
store and process suites on Native and wasm1, including the exact capture limit
and one-byte overflow boundary. It also executes real CLI workflows for
parallel output, missing/directory/symlink inputs, multiple inputs/outputs,
working-directory and dangling outputs, bypass, clean, crash recovery, and two
concurrent Native processes contending for the same digest.

The clean local regression passes 263 Native and 259 wasm1 tests, strict
all-backend compilation, formatting, 21-package architecture boundaries,
2,417-row compatibility verification, Phase 8 regression and the Phase 9
runtime gate. Merged commit, PR number and remote CI run are recorded only
after protected-main checks complete.
