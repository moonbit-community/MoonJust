# Wasm migration — 2026-11-18

## Scope and artifacts

The baseline is the **pre-migration working tree**, including the existing uncommitted changes, with one correction: strict coverage executes and outlines the spec tests on Wasm. It is not a rebuild of the old Git commit. Both release binaries use Moon/Moonrun 0.1.20261117, compiler/core 0.10.21+06da1ed44, x 0.5.7 and regexp 0.3.7. Native is a test-driver target only. No version was published.

| Wasm artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Baseline | 2,070,545 | `2c7839d706309eb37207f5f182930c431c0feb66860aec9a952e300ea79e7a6f` |
| Migrated | 2,149,278 | `86d43a01774eb429bf274fdda759654cfb77cf5334adf3834d9d2594821aed67` |

## Behavior: macOS arm64, just 1.57.0

| Wasm evidence | Before | After |
| --- | ---: | ---: |
| Package tests passed | 965 | 967 |
| Exact upstream differential identities | 1,445 | 1,442 |
| Spec identities executed and located by Wasm outline | 916 | 916 |
| Verified atomic-format refusals | 0 | 3 |
| Deferred Windows-only identities | 1 | 1 |
| Completion / raw-signal exclusions | 34 / 21 | 34 / 21 |
| Unexpected failures / unclassified identities | 0 / 0 | 0 / 0 |

The inventory contains 2,417 upstream identities. Product version and help are checked separately. No oracle snapshots were rewritten. The three formatting differences require success from the oracle, a nonzero candidate exit, exact stderr digest, empty stdout and an untouched candidate tree. The macOS CLI also preserved the content hash, mode, inode and mtime of an unformatted `0751` file and an already formatted `0644` file. A second `--init` left the first file intact. With subprocesses denied, a symlink resolved to its real path, an execute-only file was found by both `require` and `which`, and an import through an alias to itself was diagnosed as circular.

Only seven differential identities on this host require fixture-supplied facts: three exercise architecture/CPU builtins and four use a re-entry launcher. Their report rows name the inputs; all other fixtures run without those injections. Direct-child cancellation and reaping, large simultaneous binary streams, and nonzero exit status are tested with a real process. The range test checks binary bytes, a short read, zero length and an offset above 32 bits. Source reads stop at the configured limit plus one; an observed file size is only an allocation hint.

## Performance: same-host Wasm pairs

macOS 26.5.2 arm64, full profile, three interleaved batches of 15 pairs per workload. Both Wasm artifacts use the same moonrun; official just verifies workload output and calibrates the no-op fixture but does not supply performance samples. The existing full gate passed. These are observations for this host and workload, not release-wide speed claims.

| Workload | Before median (ms) | After median (ms) | After/before p95 |
| --- | ---: | ---: | ---: |
| startup-version | 10 | 11 | 1.20× |
| check-1000 | 28 | 26 | 0.96× |
| check-5000 | 67 | 44 | 0.65× |
| summary-1000 | 37 | 34 | 0.95× |
| dry-run-dag-256 | 39 | 37 | 0.97× |
| dry-run-dag-1000 | 56 | 51 | 0.88× |
| modules-dotenv | 42 | 43 | 1.14× |
| script-recipes | 45 | 44 | 1.00× |
| stdin-file | 37 | 38 | 1.03× |
| wasm-host-check | 22 | 27 | 1.26× |
| run-noops | 85 | 83 | 0.99× |

Local raw reports are under `_build/maintenance/2026-11-18/` (not published). For a repeat, build `./tests/benchmark` for Native, then run it with `--candidate NEW.wasm --baseline BEFORE.wasm --official just --profile full --enforce --output report.json`. Changes in machine load or host runtime can change the ratios.

## Cross-host gate

The same Wasm (SHA-256 above) passed on macOS arm64 and in an Ubuntu 24.04 arm64 VM using native Linux `moonrun` and official `just 1.57.0`. Rebuilding the Wasm on Linux produced identical bytes. Linux also passed all 967 Wasm tests and reported the same 2,417-identity breakdown as macOS: 1,442 exact differential matches, three verified format refusals and no unexpected failures or unclassified identities.

The Linux CLI passed the same permission, no-clobber, symlink and subprocess-denied lookup checks as macOS. Each native test driver labels the host from `core/async`, not `RUNNER_OS`; overriding that variable with the other platform's name did not change either report's identity.

An exploratory x86-64-on-arm64 Linux run under Rosetta had 18 failures; that report is retained separately, not counted as a native Linux pass. Rosetta created cache entries in fixture homes, and a missing shell returned 127 rather than a launch error. With native Linux `moonrun`, the same missing-shell fixture returns the correct diagnostic and status 1 with both the baseline and migrated Wasm. No normalization or exception was added for emulation.

Windows has not run on this working tree. CI distributes one release Wasm to all three hosts. Supplying just the two successful reports exits nonzero and does not generate an aggregate. The cross-host gate therefore remains open. See [the runner instructions](../../tests/compatibility/README.md).
