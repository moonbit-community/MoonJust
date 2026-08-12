# Phase 0-10 strict exit audit

- Review date: 2026-08-13
- Reviewed implementation baseline: `d18b64ee2bacd3afc0de6801ff3352c0b9224e2b`
- Delivery: [PR #41](https://github.com/moonbit-community/MoonJust/pull/41)
- Remediation PR CI:
  [31617660952](https://github.com/moonbit-community/MoonJust/actions/runs/31617660952)
- Delivery protected-main CI:
  [31618046344](https://github.com/moonbit-community/MoonJust/actions/runs/31618046344)
- Accepted specification: [`PROJECT_PLAN.md`](PROJECT_PLAN.md)
- Phase 10 detail: [`PHASE_10_REPORT.md`](PHASE_10_REPORT.md)

## Verdict

Phase 0-9 remain complete under their previously merged evidence. Phase 10's
first PR CI passed, the required second review found and remediated a CLI
environment entry-point gap, the remediation CI passed, PR #41 merged through
protected checks, and the resulting `main` workflow passed. Phase 10 therefore
satisfies every declared exit condition.

## Phase 10 strict review

The review traced PR-100 through PR-105 from plan text to production code,
tests, machine inventories and CI jobs. It remediated the following issues
before delivery:

- a Unix-only `/bin/sh` signal test was incorrectly eligible for Windows;
- terminal color capability was incorrectly assumed to imply stderr was a TTY;
- string-valued dotenv, tempdir and shell settings were parsed but not consumed;
- module `working-directory` was retained only for inspect JSON;
- Windows runner assertions did not normalize PowerShell CRLF output;
- the Linux platform fixture declared variables instead of the recipes exercised
  by the gate, and lacked the deterministic chooser target;
- CI invoked the real platform gate only from the Ubuntu quality job instead of
  from every Ubuntu, macOS and Windows matrix runner;
- the Windows fixture exercised PowerShell but not the separately promised
  `cmd.exe /C` recipe path;
- unsupported `--dotenv-command` was still accepted and silently ignored;
- Phase 8/10 upstream rows and CLI/settings/attribute inventories could remain
  planned or claim aggregate implementation without behavioral evidence;
- the map generator's own anchor/case validation omitted its newly generated
  Phase 8 and Phase 10 rows;
- the Phase 10 gate assumed a pre-existing upstream checkout instead of
  reconstructing the pinned oracle;
- all upstream `JUST_*` argument aliases were absent from declarative CLI
  registration, and the production entry point passed an empty environment;
- `JUST_JUSTFILE=-` could not trigger stdin capture because stdin needs were
  decided before argument parsing.

The corrected design keeps platform conditionals in adapter leaves, reports
unsupported behavior explicitly, restores the fixed oracle automatically, and
fails CI on name drift, missing reasons, absent anchors or any planned row.

## Current matrix

| Evidence | Result |
| --- | --- |
| Native tests | 300 passed, 0 failed |
| wasm1 tests | 295 passed, 0 failed |
| All stable backend checks | pass |
| Phase 10 Native/wasm compatibility gate | pass |
| Pinned upstream tangle tests | 5 passed, 0 failed |
| Local macOS aarch64 platform gate | pass |
| Upstream registration classification | 2,417 classified; 0 planned |
| First PR CI | run 31611054327 passed quality, Ubuntu, macOS and Windows |
| Second review | completed; CLI environment remediation applied |
| Remediation PR CI | run 31617660952 passed quality, Ubuntu, macOS and Windows |
| Delivery merge | PR #41 merged as `d18b64ee2bacd3afc0de6801ff3352c0b9224e2b` |
| Protected-main CI | run 31618046344 passed quality, Ubuntu, macOS and Windows |

## Compatibility boundary

The final map contains 1,844 covered registrations, 526 explicit unsupported
differences, 35 excluded completion cases and 12 not-applicable internal or
maintenance cases. Unsupported does not mean silently accepted: corresponding
CLI entries are rejected or the missing runtime behavior is named in a
machine-readable reason. Browser/wasm-gc process execution, module-aware
chooser traversal, completion generation and release tooling remain outside
the Phase 10 support claim.

## Security boundary

Interactive commands invoke user-selected external programs with inherited
terminal streams. They do not make untrusted justfiles safe. Wasm inspect stays
deny-write and deny-spawn; execution still requires an explicit policy. Process
output retention remains bounded, cancellation reaps children, temporary
scripts are exclusively created and cleaned, and compatibility diagnostics do
not expose captured stdin or environment values.

## Exit condition

All declared exit conditions are satisfied: the delivery and remediation PR
checks passed quality, Ubuntu, macOS and Windows; the second code/document
review has no open plan gap; PR #41 merged through protected checks; and the
resulting `main` workflow succeeded. Phase 10 is complete.
