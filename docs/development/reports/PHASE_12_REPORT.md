# Phase 12 Release Closure Report

## Conclusion

Phase 12 closes the functional, compatibility, test-governance, source-layout,
stable-API, platform, C-cleanup, documentation, and release-audit work. The
primary product artifacts are the `cmd/just` Native and wasm1 binaries. The
stable optional embedding entry point is `ZSeanYves/MoonJust/api`.

This is the single current release and audit report. It consolidates the
platform compatibility closure, the production C cleanup, and the final
release review so that current claims cannot drift between several reports.

The report is bound to the `main` release commit and its exact-head CI/RC
evidence. Workflows must validate the SHA checked out by the job; a merge SHA,
default-branch SHA, or missing SHA is not acceptable evidence.

CI, release, and compatibility orchestration use Python 3.11. Windows jobs use
native Python path and artifact operations and do not start Git Bash. The
historical Unix-only host-async observation harness is outside the production
build and current release gate; old non-host-async Shell helpers and release
wrappers have been removed.

## Fixed Baseline and Identity

- Upstream: `just 1.57.0`
- Upstream commit: `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- MoonBit module: `ZSeanYves/MoonJust`
- Moon metadata version: `0.1.0`
- Product and release tag version: `v0.1.0`
- Repository: `https://github.com/moonbit-community/MoonJust`
- Stable facade: `ZSeanYves/MoonJust/api`
- Shell completion generation and compatibility remain explicitly excluded.

The historical Phase 0-11 reports retain their original phase scope, test
counts, and contemporaneous identities. They are evidence snapshots, not
current release contracts.

## Source Layout and Public API

Implementation packages live under `src/*`; there is no second `internal/*`
implementation tree. Moon package files, generated interfaces, compatibility
manifests, upstream inventories, coverage aggregation, CI, and documentation
references are synchronized.

`api/pkg.generated.mbti` and `src/host_process/pkg.generated.mbti` remain
unchanged by the current implementation. The stable facade keeps its function,
error, field, and method sets. Architecture checks ensure that parser, AST,
semantic, evaluator, host, and executor implementation types do not leak
through the facade.

## Production C Cleanup

The production C sources `src/host_native/platform.c`,
`src/host_native/realpath.c`, `src/host_native/transaction.c`, and the final
`src/host_process/signal_forward.c` have been removed. Their behavior is now
provided by MoonBit native/portable adapters, system ABI declarations, or
approved `moonbitlang` backends. The production C inventory is empty.

Two C probes remain in the isolated historical host-async package:

- `spikes/host-async/process_lifecycle/process_lifecycle.c`
- `spikes/host-async/signal_probe/signal_probe.c`

They are not production sources, native stubs, or release artifacts.

The capability migration is:

| Removed source | Replacement | Compatibility boundary |
| --- | --- | --- |
| `src/host_native/platform.c` | `platform_native.mbt` and the existing portable host adapter | System ABI calls remain private FFI; OS, architecture, cwd, TTY, PID, CPU, clock, and random behavior are target-mapped. |
| `src/host_native/realpath.c` | `canonical_native.mbt` | Unix resolves symlink components; Windows retains wide-character handle APIs for drive and UNC paths. |
| `src/host_native/transaction.c` | `transaction_native.mbt` | Exclusive creation, sync, atomic overwrite/no-overwrite, permissions, executable handling, and cleanup remain covered. |
| C-only test helpers | `native_test.mbt` and `moonbitlang/async/fs` | Tests use portable async filesystem behavior; remaining system calls use target ABI directly and do not reference a project C file. |

Native behavior retains symlink and error handling, bounded range reads, EOF and
short-read behavior, exclusive temporary creation, full sync, atomic writes,
permission inheritance, read-only rejection, executable handling, and cleanup.
POSIX paths passed to libc include an explicit NUL terminator. Windows paths use
wide-character APIs and cover drive and UNC prefixes.

The static audit is:

```text
git ls-files '*.c' '*.h'
rg -n 'native-stub|moonjust_host_|extern "C"|extern "c"' src tools
```

The production C and production `native-stub` inventories are empty. Remaining
MoonBit `extern` declarations refer to system ABI or approved dependency
backends, not to a MoonJust-owned C source or an added dependency.

## Direct-Child Process and Signal Contract

Process lifecycle is delegated to `moonbitlang/async/process`: creation,
cancellation, waiting, reap, exit status, and direct-child signal status
mapping remain owned by the adapter and async runtime.

MoonJust does not install a signal handler, create a signal pipe, record a raw
first signal, forward TERM itself, or provide signal-specific diagnostics.
Signal identity, TERM forwarding, first-signal ordering, SIGINFO, and
signal-specific diagnostics are approved differences documented by ADR-0020.
Cancellation is represented as a generic interruption rather than as evidence
that MoonJust observed a particular signal.

Indirect, background, daemon, regrouped, and detached descendants are outside
the lifecycle guarantee. A descendant may retain a shared stdout/stderr pipe,
so direct-child wait/reap and pipe-reader EOF remain separate observations.
Readers continue concurrently with the direct-child wait; the adapter does not
reintroduce process-group cleanup to force descendant-held pipes closed.

The upstream `signals::forwarding` case remains an explicit Native
direct-child limitation under ADR-0019. It does not justify restoring a private
process-group or signal-forwarding implementation.

## Test Governance and Naming

Behavior-oriented test files replaced coverage-only names. Tests assert
diagnostic codes, spans, exit status, stable output content, and round-trip
behavior rather than using coverage as a feature label.

`tools/quality/check_naming.py` checks MoonBit source files, functions, methods,
and constants using only the Python standard library. It is part of the fast
runner DAG and has passing tests for both compliant and violating inputs.

## Platform and Upstream Compatibility

The supported Native matrix is Linux x86_64, macOS arm64, and Windows x86_64.
One Ubuntu-built wasm1 artifact is shared by the three Native jobs and consumed
only after checksum verification. Native, platform, signal, process, and
interactive evidence remains host-local. The official compatibility harness is
pinned to the upstream commit above and excludes completion.

The pinned inventory contains 2,417 registrations. Official non-completion
results and executable contract evidence have no unregistered failure. Results
may be classified as exact, diagnostic-exact, diagnostic-semantic,
product-identity, excluded-completion, upstream-ignored, not-applicable,
approved-difference, or failed. Approved differences do not enter the
compatibility denominator and require explicit evidence.

The two Linux invalid-UTF-8 cwd cases remain `not-applicable` for wasm1:

- `non_unicode::warn_for_non_unicode_invocation_directory`
- `non_unicode::warn_for_non_unicode_justfile_path`

This is a MoonX host boundary limitation, not a MoonJust compatibility failure.
Native passes both cases exactly. Platform path and newline behavior are
covered by the macOS and Windows gates without workload-specific result
hardcoding.

## Strict Local Verification

The current implementation was rechecked locally with:

```text
python3 -m compileall -q tools
python3 tools/runner.py test-tools
python3 tools/upstream/verify_manifest.py
python3 tools/quality/check_naming.py
python3 tools/verification/checks/signal_policy.py
moon check --target all --warn-list +73 --deny-warn
moon test --target native       # 1111 passed, 0 failed
moon test --target wasm         # 1097 passed, 0 failed
python3 tools/runner.py run --mode fast
```

The checks cover formatting, architecture boundaries, naming, all-target type
checking, tools, the 2,417-registration manifest, signal policy scenarios, and
the complete Native/wasm test matrices. Stable generated interfaces remain
unchanged.

Release artifacts, three-platform evidence, ASan/UBSan, and RC evidence are
CI-owned checks and must be attached to the exact release commit. A macOS local
result cannot replace Linux, Windows, or release-runner evidence.

## Coverage, Benchmark, and Release Policy

Native and Wasm raw coverage reports are merged in the release-evidence job.
Only the merged overall coverage threshold of 80% can fail the gate. Changed
line, area, package baseline, and benchmark fixed-time values remain report
fields and do not fail the current release policy.

Main pushes and manual releases run report-only benchmarks on Linux, macOS, and
Windows. They require successful execution, complete samples, valid schema,
artifact hashes, commit identity, and toolchain provenance. They do not impose
an absolute timing or baseline-ratio threshold.

Artifact size, repeatability, source-package, policy, tamper-resistance,
supply-chain, MoonX asset, upgrade-rehearsal, and aggregate release evidence
remain explicit release checks. Formal tag creation, publication, and GitHub
Release creation are maintainer actions performed after candidate verification.

## Final Release Review

The current release conclusion is that functionality, stable API, Native/wasm1
behavior, platform adapters, compatibility classification, and production C
cleanup are complete. The isolated host-async probes are historical research
artifacts and are not part of the production build or current release gate.

The same exact head must provide all release exits:

- Native, Wasm, warning-deny, architecture, naming, and tools checks;
- the upstream registration manifest, official non-completion harness, and
  async-only signal evidence;
- Linux, macOS, and Windows Native artifacts, shared wasm1 hash, size,
  repeatability, supply-chain, and aggregate release evidence;
- the merged Native/Wasm overall coverage gate at 80%;
- three-platform report-only benchmark execution, sample completeness, and
  provenance;
- stable API, MoonBit package interfaces, source package, policy, tamper, and
  upgrade-rehearsal checks.

Completion, the two Linux MoonX invalid-UTF-8 cwd cases, descendant cleanup
outside the direct-child contract, and ADR-0020 raw-signal differences are
explicit scope boundaries rather than hidden failures.

## Remote Exit

The final release commit must be pushed as an ordinary commit. Its exact head
must pass the protected-main CI and release-candidate checks for functionality,
compatibility, coverage, warnings, repeatability, tools, official differential
evidence, artifact size, and provenance. Evidence must show every approved
exception explicitly; no gate may be weakened through broad normalization or
implicit process-tree cleanup.

Historical evidence remains in the `PHASE_0_REPORT.md` through
`PHASE_11_REPORT.md` files. The current release entry points are this report and
[`RELEASE_AUDIT.md`](RELEASE_AUDIT.md).
