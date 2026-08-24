# C Cleanup Report

## Scope

This report records the host-native C cleanup completed on the Phase 12
candidate branch. The exact implementation head is
`e49b018819f10a8b3e770f82355f6fce79368ccc`, carried by Draft PR #59. The
cleanup removes project-owned production C that duplicated filesystem,
platform, and process-group behavior while retaining only the signal stub and
isolated research probes explicitly approved by the plan.

Tracked project C sources after the cleanup:

```text
src/host_process/signal_forward.c
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

- The current C inventory is exactly the three files listed above.
- `src/host_native/moon.pkg` has no `native-stub` entries.
- `src/host_process/moon.pkg` is the only production package with a
  `native-stub` list, and it contains only `signal_forward.c`.
- The two spike packages retain their own explicitly isolated C probes.
- No removed `moonjust_host_*` symbol remains.
- Remaining MoonBit `extern "C"` declarations are system ABI calls or calls
  into approved `moonbitlang` backends; they are not project-owned C sources.

Process execution now uses `moonbitlang/async/process` for direct-child
creation, cancellation, wait, reap, and signal status mapping. Indirect,
background, daemon, and detached descendants are outside the lifecycle
contract. A descendant that retains a shared stdout/stderr pipe can therefore
keep the reader open after the direct child has been reaped; the adapter keeps
concurrent readers and does not restore group cleanup to change that behavior.

## Cross-platform verification

The exact-head GitHub run `32705322439` completed successfully for:

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
moon test --target native --no-parallelize  # 1113/1113
moon test --target wasm --no-parallelize    # 1097/1097
python3 tools/quality/check_naming.py
python3 tools/quality/check_naming_test.py
python3 tools/upstream/verify_manifest.py
```

`api/pkg.generated.mbti` remains byte-identical to the preceding candidate
(`3df9b3d67626be98551e1ca45e417d64315dda2c956e0e1027405c01064efa98`).

## Remaining release gates

The PR event intentionally skipped production coverage, hosted performance
trend, aggregate release evidence, and release artifact upload steps. Those
remain CI/Release Candidate responsibilities and were not inferred from the
local macOS run. The known independent exceptions remain the artifact-size
gate and Windows Native performance for `dag-1000` and
`project-parameters`; this C cleanup does not lower or hide those gates.

No merge or push to `main` is part of this report. The report and the two
existing ADR document changes are delivered on the feature branch for the
next exact-head CI/RC decision.
