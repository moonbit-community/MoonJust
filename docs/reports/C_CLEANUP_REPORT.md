# C Cleanup Report

## Scope

This report records the host-native C cleanup completed on the Phase 12
candidate branch, the direct-child process lifecycle migration delivered by
PR #60, the subsequent CI/script migration, and the async-only signal
migration. The cleanup removes all project-owned production C; only the
isolated research probes remain outside the production inventory.

There is no production C source after ADR-0020.

The host-async validation package retains two isolated test probes:

```text
spikes/host-async/process_lifecycle/process_lifecycle.c
spikes/host-async/signal_probe/signal_probe.c
```

Third-party sources under `.mooncakes` and generated files under `_build` are
outside this inventory. No new project C source, native stub, dependency, or
public MoonBit API was added.

## Replacement map

| Removed source | Replacement | Compatibility boundary |
| --- | --- | --- |
| `src/host_native/platform.c` | `platform_native.mbt` plus the existing portable host adapter | System ABI calls are private FFI declarations; OS, architecture, cwd, TTY, PID, CPU, clock, and random behavior remain mapped by target configuration. |
| `src/host_native/realpath.c` | `canonical_native.mbt` | Unix resolves symlink components with `readlink`; Windows retains wide-character handle APIs for drive and UNC paths. |
| `src/host_native/transaction.c` | `transaction_native.mbt` | Exclusive creation, sync, atomic overwrite/no-overwrite, permission handling, executable handling, and cleanup remain in the HostFs adapter. |
| C-only test helpers | `native_test.mbt` behavior probes and `moonbitlang/async/fs` | Tests use portable async filesystem behavior where available. The remaining test-only libc/Win32 externs call platform system APIs directly and do not reference a project C file. |

Range reads and bounded source loading were also kept on the native streaming
path for non-regular files. FIFO tests use one open stream and preserve EOF and
short-read behavior; Windows skips the Unix-only FIFO capability instead of
claiming a fabricated equivalent.

## Static audit

The following audits were run after the cleanup:

```text
git ls-files '*.c' '*.h'
rg -n 'native-stub|moonjust_host_|extern "C"|extern "c"' src tools
```

Results:

- The production C inventory is empty.
- `src/host_native/moon.pkg` has no `native-stub` entries.
- `src/host_process/moon.pkg` has no `native-stub` entries.
- The host-async validation package retains its two explicitly isolated C probes.
- No removed `moonjust_host_*` symbol remains.
- Remaining MoonBit `extern "C"` declarations are system ABI calls or calls
  into approved `moonbitlang` backends; they are not project-owned C sources.

Process execution now uses `moonbitlang/async/process` for direct-child
creation, cancellation, wait, reap, and signal status mapping. MoonJust does
not install a signal handler, create a signal pipe, record first raw signals,
or provide TERM forwarding and signal-specific diagnostics. Indirect,
background, daemon, and detached descendants are outside the lifecycle
contract. A descendant that retains a shared stdout/stderr pipe can therefore
keep the reader open after the direct child has been reaped; direct-child wait
and pipe-reader EOF remain separate observations.

## Cross-platform verification

The C/process cleanup evidence was recorded on PR #60. The current CI policy is
maintained by the Python-only verification path and the exact-head main run
`32761267363` (the final head for this report must be checked again after this
documentation/script change). The relevant host checks include:

- `Quality gates`
- `Verify gate`
- `One-to-one contract evidence`
- `Compatibility gate`
- `Native smoke (ubuntu-latest)`
- `Native smoke (macos-latest)`
- `Native smoke (windows-latest)`
- shared Ubuntu-built wasm1 asset and checksum validation

The three Native smoke jobs completed Native verification, platform
compatibility evidence, and artifact-hash validation on their own hosts. The
Windows symlink probe now uses the async filesystem behavior API, removing the
previous custom helper failure. Native, platform, signal, process, and
interactive evidence remains host-local; only the validated shared wasm1 asset
crosses hosts.

The documented Linux MoonX invalid-UTF-8 cwd cases remain `not-applicable` host
limitations, not cleanup regressions:

- `non_unicode::warn_for_non_unicode_invocation_directory`
- `non_unicode::warn_for_non_unicode_justfile_path`

Local second-pass checks on macOS also passed:

```text
moon fmt --check
moon check --target all --warn-list +73 --deny-warn
moon test --target native --no-parallelize  # 1110/1110
moon test --target wasm --no-parallelize    # 1097/1097
python3 tools/quality/check_naming.py
python3 tools/quality/check_naming_test.py
python3 tools/upstream/verify_manifest.py
```

`api/pkg.generated.mbti` remains byte-identical to the preceding candidate
(`3df9b3d67626be98551e1ca45e417d64315dda2c956e0e1027405c01064efa98`).

## Current CI and helper-script policy

All CI orchestration and compatibility gates now enter through Python 3.11,
`tools/runner.py`, or a dedicated Python tool. Non-host-async Shell helpers and
the old release wrappers were deleted; Windows CI does not start Git Bash.
The only retained Shell files are the explicitly Unix-only host-async
historical observation harness under `tools/spikes/` and `spikes/host-async/`;
it is not part of the current production verification gate.

Production coverage merges Native and Wasm raw reports in the release-evidence
job and gates only overall coverage at 80%. Changed-line, area, and package
baseline values remain report fields. Main and manual release benchmark jobs
run on Linux, macOS, and Windows in report-only mode; they require complete
samples, successful execution, and provenance, but impose no fixed timing
threshold.

The direct-child process contract remains unchanged: indirect, background,
daemon, and detached descendants are outside lifecycle guarantees, and a
descendant holding a shared stdout/stderr pipe may delay reader EOF after the
direct child has been reaped.

Artifact size, release evidence, and exact-head CI remain explicit release
checks. This report does not treat historical timing exceptions or old Shell
entrypoints as current policy.
