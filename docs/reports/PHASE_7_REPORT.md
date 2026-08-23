# Phase 7 completion report

- Status: Implemented; Phase 7 exit passed
- Date: 2026-08-08
- Strict second review: passed against `main` at
  `d80d8a394301fe4286c6a4b7b00592e586a9e029`
- Upstream baseline: `just 1.57.0` at `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Required targets: Native and wasm1

Phase 7 delivers the complete pre-execution model for filesystem transactions,
dotenv and environment loading, recipe invocation parsing, working-directory
selection, and CLI environment composition. Recipe commands are deliberately
not executed: process construction and execution remain Phase 8 capabilities.

## Delivered contracts

| Unit | Delivery | Evidence |
| --- | --- | --- |
| PR-070 | Native atomic replace/no-overwrite, UTF-16 Windows canonicalization, policy-aware wasm1 transactions, cleanup and typed denial | `src/host_native`, `src/host_wasm/transaction`, `tools/check_hostfs_policy.sh` |
| PR-071 | Redacted dotenvy-compatible parser, file search and merge precedence, required/override/list modes, command sources and explicit host environment | `src/environment`, `tools/check_dotenv_compat.sh` |
| PR-072 | Positional and variadic parameters, recipe-local options, flags, repetition, patterns, expression values, usage and stable errors | `src/invocation`, `tools/check_invocation_compat.sh` |
| PR-073 | Invocation/project/module/evaluation/recipe cwd model, imports, modules, symlink display paths, `no-cd`, settings and attributes | `src/workdir`, `tools/check_workdir_compat.sh` |
| PR-074 | `--set NAME VALUE`, shell override ordering, tempdir selection, platform rules and complete child-environment precedence | `src/environment/composition.mbt`, `tools/check_environment_compat.sh` |

## Compatibility evidence

- The pinned upstream map assigns 188 registrations to Phase 7 executable
  Native/wasm1 family anchors: 51 dotenv, 86 invocation, 30 working-directory,
  and 21 CLI environment registrations.
- The audit moved 255 registrations whose first observable prerequisite is
  recipe execution, cache behavior, or product tooling to Phase 8, 9, or 10.
  None is counted as Phase 7 coverage.
- Invocation has 20 package tests plus 11 argv and three Native/wasm1 usage
  differential cases. It validates invocations before the Phase 8 boundary and
  never receives a process capability.
- Dotenv has parser, discovery, precedence, command-source, platform-name, and
  secret-redaction tests plus six fixtures against pinned `dotenvy 0.15.7`.
- Working-directory selection has nine upstream model cases and two
  Native/wasm1 CLI cases. Environment composition has seven upstream cases
  covering variable overrides, shell ordering, tempdir, and full child env
  precedence.

## Capability and security boundaries

- Temporary files are same-directory, mode `0600`, synchronized before commit,
  and cleaned on failed commit without hiding the original typed error.
- The writable wasm1 transaction adapter is a separate leaf package. The
  Phase 6 inspection adapter and `policies/inspect.toml` remain read-only.
- Environment and CLI override containers do not derive `Debug`. Dotenv errors
  retain structural location/status only and omit values, command strings,
  argv, child stderr, and environment entries.
- Core invocation, cwd, and environment composition are deterministic models;
  ambient filesystem, environment, and platform facts enter through explicit
  Host contracts.

## Verification

- `moon check --target all --warn-list +73`: pass.
- `moon test --target native`: 211 passed, 0 failed.
- `moon test --target wasm`: 208 passed, 0 failed.
- All five Phase 7 executable gates pass locally and in the functional PR CI.
- `tools/check_architecture.sh`: core packages remain separated from adapter
  leaves and the Phase 8 executor boundary remains explicit.
- `moon info && moon fmt`: generated interfaces and formatting were clean for
  each functional PR.

## Publication evidence

| Delivery | Merge commit | PR CI | Post-merge `main` CI |
| --- | --- | --- | --- |
| [PR #28 / PR-070](https://github.com/moonbit-community/MoonJust/pull/28) | `7f6a3754ee9c82682f61940f6c1dfa1a5f4df21f` | [31174692583](https://github.com/moonbit-community/MoonJust/actions/runs/31174692583) | [31174873886](https://github.com/moonbit-community/MoonJust/actions/runs/31174873886) |
| [PR #29 / PR-071](https://github.com/moonbit-community/MoonJust/pull/29) | `0035e84beb4f141e12afb66833d64284d55c0029` | [31178081592](https://github.com/moonbit-community/MoonJust/actions/runs/31178081592) | [31178334856](https://github.com/moonbit-community/MoonJust/actions/runs/31178334856) |
| [PR #30 / PR-072](https://github.com/moonbit-community/MoonJust/pull/30) | `3b34f76f6a2542486602720b355c09168174b2ab` | [31240814162](https://github.com/moonbit-community/MoonJust/actions/runs/31240814162) | [31240881314](https://github.com/moonbit-community/MoonJust/actions/runs/31240881314) |
| [PR #31 / PR-073](https://github.com/moonbit-community/MoonJust/pull/31) | `c73037fb9f5132cd53fb3c91e6705624467345f5` | [31242090566](https://github.com/moonbit-community/MoonJust/actions/runs/31242090566) | [31242179491](https://github.com/moonbit-community/MoonJust/actions/runs/31242179491) |
| [PR #32 / PR-074](https://github.com/moonbit-community/MoonJust/pull/32) | `3f1c1363c43e57c4881559077c1180507a1a8cfd` | [31243986487](https://github.com/moonbit-community/MoonJust/actions/runs/31243986487) | [31244169707](https://github.com/moonbit-community/MoonJust/actions/runs/31244169707) |
| [PR #33 / second-audit remediation](https://github.com/moonbit-community/MoonJust/pull/33) | `d80d8a394301fe4286c6a4b7b00592e586a9e029` | [31244887123](https://github.com/moonbit-community/MoonJust/actions/runs/31244887123) | [31244990807](https://github.com/moonbit-community/MoonJust/actions/runs/31244990807) |

Every listed PR and post-merge run completed Quality gates plus Ubuntu, macOS,
and Windows native smoke jobs successfully. The PR-074 Windows job was rerun
after a transient package-registry timeout and then passed without code changes.

## Strict second-review verdict

The second pass found no missing functional unit inside the declared Phase 7
boundary, but it found three release-evidence defects: all 443 provisional
Phase 7 upstream rows were still marked planned, the Phase 7 corpus and report
were absent, and the aggregate local gate omitted the environment-composition
differential. The remediation adds deterministic executable anchors for the
188 in-scope registrations, defers later-runtime cases honestly, publishes the
structured manifests, and includes all five gates in `python3 tools/runner.py run --mode verify`.

PR #33 closed all three findings. Its PR CI and post-merge `main` CI completed
Quality gates plus Ubuntu, macOS, and Windows jobs successfully; the aggregate
gate executed all five Phase 7 differentials and the 211/208 full target
matrix. No unresolved gap remains inside the declared Phase 7 scope, so the
Phase 7 exit is passed.
