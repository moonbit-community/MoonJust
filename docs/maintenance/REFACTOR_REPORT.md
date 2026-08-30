# Maintenance Report: Performance Recovery and Logic Rewrite

## Purpose

This report records the complete maintenance line carried by the two feature
branches opened after the 0.1.1 preparation:

| Pull request | Branch | Range | Purpose |
| --- | --- | --- | --- |
| [#68](https://github.com/moonbit-community/MoonJust/pull/68) | codex/performance-root-cause | 8ae279fe..a9c5fd8 | Measure and recover Native/Wasm performance without changing just 1.57 behavior |
| [#69](https://github.com/moonbit-community/MoonJust/pull/69) | codex/logic-rewrite | a9c5fd8..HEAD | Rebuild the repository around one execution chain and pure MoonBit verification |

PR #69 contains the complete PR #68 commit line. This document is a work
record, not an architecture contract. The maintained package boundaries and
execution invariants are documented in [docs/ARCHITECTURE.md](../ARCHITECTURE.md).

## Current Validation Work

The 0.1.2 consistency pass now uses `moon.mod` as the product version source
and checks the candidate static `--version` response before running cases.
Native and Wasm both report `moonjust v0.1.2`, with the version digest updated
to the new bytes.

The compatibility runner reads all 2,417 identities from the pinned just
1.57.0 inventory and writes one JSON row per identity. Every source-only row
retains its upstream anchor and original input/expected assertion text, while
only real executable fixtures contribute to executed coverage. The current
local report contains 1,771 executed identities (1,767 exact and 4 pinned
known differences), 30 completion exclusions, 14 runtime-signal exclusions,
and 602 source-snapshot identities still awaiting executable migration. The
runner validates deterministic official output snapshots and reports source
evidence separately; CI does not enable strict coverage until that count is
zero. The executable corpus currently has 1,322 exact matches, 6 pinned known
differences, and 0 failures.

The benchmark runner now generates larger check, format, summary, DAG, no-op,
module, script, and Wasm-host workloads. It performs warmups and interleaved
candidate/oracle samples across batches, reports median/p95 ratios and a
sample-level ratio interval, and writes gate-compatible JSON. Wasm invocations
use `moonrun <artifact> -- <program arguments>`; the separator is not passed
to MoonJust. CI runs native and Wasm benchmark jobs on every OS matrix entry
and uploads both reports.

The first internal-spec migrations cover the upstream path, invocation,
attribute, lexer, and parser units with one assertion per migrated id in
`internal/*/upstream_*_test.mbt`. The remaining upstream identities are
indexed in the pinned source snapshot
`tests/compatibility/upstream/just-1.57.0/upstream-fixtures.txt`; each block
preserves the upstream test body, source location, input, and expected
assertion text for audit and future executable promotion. These rows are
explicitly unclassified until a real MoonBit assertion or black-box fixture is
registered.

## Starting Point

The common upstream baseline was 8ae279fe, the 0.1.1 preparation commit.
Remote benchmarks showed that Linux and macOS were generally close to official
just, but Windows planning workloads and end-to-end Wasm workloads were not:

- Windows dag-1000 and project-parameters were about 4.08x and 5.16x.
- Windows noops-100 was about 1.28x, proving that process creation alone
  could not explain the planning regressions.
- Package-level Wasm computation was generally 2-4x Native while end-to-end
  workloads reached roughly 8-38x, locating most of the excess at runtime,
  filesystem, environment, and process host boundaries.
- Linux/macOS large-file parsing was already near official just, so a lexer or
  parser rewrite was not justified by the evidence.

The maintenance work kept observable just 1.57 behavior fixed while changing
internal interfaces freely. It also kept all MoonJust product logic in MoonBit.

## PR #68: Performance Root-Cause Work

### Measurement and attribution

The branch separated fixed startup cost, project loading, semantic work,
planning, process setup, and runtime/host overhead. It added opt-in performance
tracing and minimum runtime probes, recorded resolved Moon/Moonc/Moonrun and
official just identities, and moved comparisons toward interleaved candidate /
official samples instead of unrelated historical timings.

The experiments established four actionable causes:

1. Environment, platform, current-directory, and source facts were collected
   more than once during a single invocation.
2. Wasm made redundant canonicalize/read/metadata calls across the host
   boundary and paid async-runtime startup even for requests that could finish
   synchronously.
3. Dry-run planning materialized runtime tasks and dependency structures that
   could never execute.
4. Windows repeated path conversion, executable resolution, and command-wrapper
   work for equivalent commands.

### Correctness fixes required by optimization

Optimization exposed ordering-sensitive behavior. The branch therefore fixed
loader candidate error selection, preserved project dependency diagnostics,
kept diagnostic probes non-fatal, and retained the async-owned signal boundary.
These fixes were treated as prerequisites rather than benchmark exceptions.

### Host and loading changes

- Reused one portable Host snapshot per invocation.
- Fused Wasm source reads so regular-file data was not fetched again through a
  separate host operation.
- Added source-buffer size hints and reused canonical single-root compilation.
- Skipped empty dependency validation without skipping non-empty diagnostics.
- Avoided cygpath for paths already expressed as Windows drive paths.
- Preserved read limits and error behavior in the regular-file check fast path.

The load cache remained invocation-local and ends before recipe execution, so
recipes still observe files changed during the run.

### Planner and dry-run changes

- Avoided constructing an execution host for requests that only print a dry
  run.
- Added a synchronous planner only for proven-safe dry-run shapes.
- Kept empty DAGs on the optimized path and skipped runtime task materialization
  where no command can execute.
- Left scripts, backticks, effectful builtins, modules, --explain, and other
  unsupported shapes on the full planner with explicit eligibility checks.

The earlier whole-planner experiment at 7cd23d5 was not imported because its
local DAG result regressed from about 1.08x to 1.42x.

### Wasm request fast paths

Static CLI requests avoid the async runtime. Explicit summary, format, check,
recipe parsing, unchanged formatting, and empty dry-run requests use narrow
synchronous paths only when their inputs prove equivalence; otherwise they
return to the normal application path. The branch also measured post-link
wasm-opt behavior and runtime floors. The later logic rewrite removed the
custom release pipeline, so ordinary moon build/moon publish does not claim an
implicit external post-link pass; the product-code improvements and release
profile choices that survive normal Moon builds were retained.

### Performance branch commit ledger

The complete branch consists of the following groups:

- Measurement and CI: 401057c, a29af5d, 08d476b, 24da8d2, 8fc0057,
  48ee86b, da618da, cfdcf29, 7b66506.
- Compatibility protection: 5480c4c, 564baea, ca267d2.
- Host/loading: 33e159d, dcf109a, 7bd8459, e46b400, 87a1a92,
  3882e02.
- Planning/query: a4103bd, bab2425, e338885, 3566db3, 2622abd.
- CLI/Wasm fast paths: 7a332da, cab6390, 99f0d47, 8b20ced, 11a045c,
  a92b406, b0fd9aa, 8f69ae4, a9c5fd8.
- Build/profile maintenance: 62feba4, 2f2aeed, 2f83d95.

## PR #69: Pure MoonBit Logic Rewrite

### Product boundary and entrypoint

MoonJust became a binary-only module. The public api facade and its stable
library promise were removed, cmd/just was replaced by the root executable,
and moon run . became the single product entrypoint. Root code now chooses the
Native or portable adapter, delegates the request, writes the final response,
and exits; it does not own project loading or planning rules.

The metadata version moved to 0.1.2 because this is an intentionally breaking
package-surface change even though the executable compatibility contract is
preserved.

### One execution chain

The previous patch-shaped orchestration was replaced by the maintained flow:

~~~text
main
  -> application.classify_request
  -> application.prepare_project
  -> project.load_snapshot
  -> query | planner
  -> runtime.execute_plan
  -> application.render_response
  -> main.write_and_exit
~~~

Each stage owns its data lifetime. Project loading produces immutable facts;
query is read-only; planner creates plans but never processes; runtime executes
an existing plan and cannot reload the project. Static and safe Wasm fast paths
terminate early or rejoin this same chain rather than building parallel product
architectures.

### Package and file reorganization

- Moved reusable implementation into internal/ and removed the old src/
  compatibility layout.
- Replaced executor with planner and absorbed scheduler models into planner
  while keeping runtime coordination in runtime.
- Introduced project as the owner of load input, immutable snapshot,
  preparation, and semantic compilation.
- Moved deterministic query ordering and display-width behavior into query.
- Reduced application to routing, project preparation, cross-package
  orchestration, response creation, and error conversion.
- Split large parser, evaluator, semantic, planner, runtime, builtin, and
  process files by lifecycle responsibility rather than by historical patch.
- Removed dead synchronous wrappers and renamed ambiguous entry, input,
  plan_*, and static files to names that describe their responsibility.

### Host ownership

The Host contract is now the root internal/host package. It contains only
capability traits, value types, and HostError. Its child packages are:

- host/fs: reusable read/write algorithms;
- host/native: Native filesystem, clock, platform, transaction, and cache
  adapters;
- host/process: process execution, resolution, session state, scripts, and
  signal policy;
- host/wasm: portable read-only and process-enabled adapters;
- host/wasm/transaction: policy-aware portable transactions;
- host/testkit: the deterministic FakeHost used only by tests.

The move was first performed mechanically (877a348) and then tightened by
removing cache and test-double ownership from the contract package (1704579).

### Project, query, planner, runtime, and application ownership

Subsequent stages moved source preparation to project (b9cbf42), effect and
dry-run eligibility to their domain owners and ordering/width behavior to
query (57be082), simplified the public application orchestration surface
(be052ec), and isolated target fast paths behind one root result model
(493e04f). These were ownership moves, not new compatibility shortcuts.

### Test and tool replacement

The old contract-count, architecture-name, file-layout, release-readiness,
Python, Rust, shell, and spike systems were removed. They were not copied into
new wrappers. The replacement is a smaller functional verification surface:

- package-local MoonBit behavior tests for CLI, source, parser, loader,
  semantic, project, query, planner, runtime, and Host testkit behavior;
- tests/compat, a MoonBit black-box runner that executes MoonJust and official
  just 1.57.0 in isolated roots;
- tests/platform, a real candidate/oracle platform differential;
- tests/benchmark, an equivalence-first interleaved paired benchmark;
- tests/testkit, shared MoonBit process and filesystem support.

The compatibility runner compares declared status, stdout, stderr, merged
output, filesystem effects, and live-output observations byte-for-byte. Every
case must have a unique ID and an upstream anchor. The six retained differences
are restricted to the declared field and pin the candidate bytes with MoonBit
SHA-256, so a new diagnostic cannot pass under an old reason.

Historical ADRs and delivery reports were restored under docs/development/.
They remain useful engineering records but no longer act as current package,
release, or layout contracts. Current reports live in docs/maintenance/ and
current architecture lives at docs/ARCHITECTURE.md.

### CI recovery

The final workflow uses the latest MoonBit distribution and runs:

- Native check, tests, release build, and platform differential on Ubuntu,
  macOS, and Windows;
- Wasm check, tests, release build, and artifact upload;
- the just 1.57 differential and paired benchmark on Ubuntu;
- moon info and moon fmt --check.

Two portability defects in the new runners were fixed after remote execution:
path-based candidate programs are resolved before entering case directories,
and platform comparisons use one stable shared working directory. The final PR
run before this report, [33303956394](https://github.com/moonbit-community/MoonJust/actions/runs/33303956394),
passed all six jobs.

## Compatibility Result

The maintained differential corpus contains 1,328 executable scenarios:

- 1,322 exact matches;
- 6 explicit known differences;
- 0 failures.

The six differences are two product-identity outputs (--version and --help),
one unstable-function diagnostic presentation, and three dotenv option-conflict
diagnostics. No new difference was added to make the rewrite pass. Completion
remains outside the claimed compatibility surface.

Native and Wasm package tests each pass 18 behavior tests. Those counts are
reported only as run results; they are not quality gates or compatibility
claims.

## Performance and Size Protection

The rewrite was compared with a9c5fd8 using the same local toolchain and
interleaved samples:

| Evidence | Result |
| --- | --- |
| Native, 31 paired rounds | median 1.00x, p95 0.75x |
| Wasm, 31 paired rounds | median 1.00x, p95 1.00x |
| Native artifact size | +0.15% |
| Wasm artifact size | +0.44% |
| Candidate vs official local dry-run sample | median 1.00x, p95 0.80x |

The numbers are regression evidence for the rewrite, not universal performance
claims. The remote CI smoke uses integer-millisecond samples and is intentionally
too coarse to replace paired profiling. No baseline optimization was restored
through a cross-layer flag or duplicate execution path.

## Removed Systems

The rewrite intentionally deleted the public api, cmd/just, src/executor,
src/scheduler, all spikes, the custom release workflows, and the repository's
Python/Rust/shell/C verification implementations. MoonBit's standard
moon publish remains the packaging path. Historical documents describing the
removed systems are retained under docs/development/ and clearly labeled as
historical.

## Delivery Verification

The branch passed:

~~~text
moon info && moon fmt
moon check --target native
moon check --target wasm
moon test --target native
moon test --target wasm
moon build --release --target native .
moon build --release --target wasm .
moon run --target native ./tests/compat -- --candidate ... --official just
moon run --target native ./tests/platform -- --candidate ... --official just
moon run --target native ./tests/benchmark -- --candidate ... --official just --rounds 15
moon publish --dry-run
~~~

moon publish --dry-run received the successful registry dry-run response; the
then-current CLI returned exit 255 after that success, which was treated as a
Moon tool behavior rather than a MoonJust product result. The final merge is
accepted only after the resulting main commit passes the maintained CI matrix.
