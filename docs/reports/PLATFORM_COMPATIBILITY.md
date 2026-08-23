# Platform Compatibility Closure

This is the current platform-focused result for MoonJust. It supersedes
platform conclusions in older phase reports, but does not change the pinned
upstream baseline or the release-readiness verdict.

## Scope

- Upstream behavior: `just 1.57.0`, commit
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`.
- Native targets: Linux x86_64, macOS arm64, and Windows x86_64.
- Wasm target: one Ubuntu-built wasm1 asset, downloaded and checked by all
  three Native jobs.
- Completion, product identity, upstream-ignored, and explicit
  `not-applicable` cases are reported separately from compatibility failures.

## Evidence

The platform run is GitHub Actions CI
[`32353564260`](https://github.com/moonbit-community/MoonJust/actions/runs/32353564260)
at candidate commit `41b09535ff855ba715f5d29a8eaae82e9a5b68f1`. Its platform
gates and official harness logs show no unapproved platform failures:

| Host job | Native differential | Shared wasm1 differential | Signal/platform gate | Job conclusion |
| --- | --- | --- | --- | --- |
| Ubuntu Linux x86_64 | `failed=0` | `failed=0`, 2 explicit `not-applicable` | passed; 13 signal cases | artifact-size gate only |
| macOS arm64 | `failed=0` | `failed=0` | passed; 14 signal cases | artifact-size gate only |
| Windows x86_64 | `failed=0` | `failed=0` | passed; Windows platform matrix | dependency-normalized size reproducibility gate only |

The shared wasm asset job passed. The overall workflow remains red because
coverage, contract, quality, and artifact-size/reproducibility gates are
independent work; those failures are not platform compatibility failures.

## Accepted Host Limitation

The pinned upstream Linux suite contains two tests that create a directory with
an invalid UTF-8 byte (`foo\\xFF`):

- `non_unicode::warn_for_non_unicode_invocation_directory`
- `non_unicode::warn_for_non_unicode_justfile_path`

MoonJust Native passes both cases exactly. The wasm harness reaches a Rust host
panic in the MoonX/`moonrun` environment boundary and does not produce a useful
MoonJust wasm result. The raw evidence contains an `std/src/env.rs` panic with
the invalid path bytes. These two wasm rows are therefore explicitly classified
as `not-applicable` in
[`compatibility-exceptions.toml`](../../tests/upstream/just-1.57.0/compatibility-exceptions.toml)
and in the Linux oracle. They are not silently normalized to `exact` and are
not counted as MoonJust semantic failures.

The MoonX maintainers have confirmed that supporting this uncommon host case is
not currently planned. MoonJust does not add a workaround or claim arbitrary
non-UTF-8 cwd support for wasm1. If MoonX later changes this host boundary, the
explicit stale-state checks require a fresh platform audit.

## Boundary

This closure means that supported cross-platform command, path, environment,
process, signal, Native/wasm1 policy, and official differential behavior is
resolved for the tested matrix. It does not mean the product is release-ready:
the repository still has separate compatibility-evidence, coverage, quality,
performance, and artifact-size work.

The platform-specific oracle files are documented in
[`tests/upstream/NOTICE.md`](../../tests/upstream/NOTICE.md): Darwin, Linux,
and Windows snapshots are never compared across hosts.
