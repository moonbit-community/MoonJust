# Phase 11 Completion Report

- Scope: PR-110 through PR-114 from `docs/PROJECT_PLAN.md`
- Compatibility baseline: `just 1.57.0` at `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- Candidate identity: `0.7.0-alpha.1`
- Local review date: 2026-08-13
- Delivery: [PR #43](https://github.com/moonbit-community/MoonJust/pull/43)
- Remote evidence: first successful PR CI
  [31667796269](https://github.com/moonbit-community/MoonJust/actions/runs/31667796269)
  and second-review PR CI
  [31669564990](https://github.com/moonbit-community/MoonJust/actions/runs/31669564990)
- Strict review: [`PHASE_0_11_AUDIT.md`](PHASE_0_11_AUDIT.md)
- Publication boundary: candidate preparation only; formal publication, tags
  and GitHub Releases are maintainer-only and were not performed

## Delivered contracts

| PR | Contract | Local exit evidence |
| --- | --- | --- |
| PR-110 | Complete Mooncakes metadata, safe source archive, executable public API guide and exact MoonX coordinate | `moon package`, source verifier, 3 API documentation tests and local MoonX staging |
| PR-111 | Explicit deny, inspect, CI and execute policies with security documentation | explicit deny, omitted-section default deny, read-only query and controlled/full execution smoke tests |
| PR-112 | Linux, macOS, Windows and wasm1 candidate artifacts with deterministic archives and checksums | platform matrix workflow, extraction verifier, exact version execution and external/embedded checksum validation |
| PR-113 | Dependency/license audit, CycloneDX SBOM, SLSA-compatible provenance and OIDC candidate attestation | exact three-dependency audit, commit/toolchain/target binding and twelve-class tamper rejection |
| PR-114 | Cache-independent source rebuild plus previous-candidate upgrade and rollback | fresh source tree, caches disabled, Phase 10 query/execution parity and exact-byte rollback |

## Mooncakes and MoonX

`moon.mod` now declares the source description, repository, Apache-2.0 license,
README and four search keywords. The source archive verifier rejects unsafe or
duplicate paths, credentials, build/cache content, missing publication files,
metadata drift and an unnumbered prerelease. The archive is rebuilt in a fresh
source directory from the three exact resolved dependency versions with global
dependency/build caches disabled.

The candidate coordinate is
`moonbit-community/MoonJust/cmd/just@0.7.0-alpha.1`. A local HTTP staging
registry reproduces MoonX's exact wasm and `.sha256` asset paths. Every test
uses a fresh MoonX home: the valid asset downloads and executes, while a
corrupt sidecar is rejected with a checksum mismatch. No package was formally
published.

## Policy and artifacts

`deny.toml` grants no environment, filesystem, network or process capability.
An intentionally incomplete policy proves omitted sections remain deny by
default. `inspect.toml` permits repository reads only, `ci.toml` adds the
controlled build write/process surface, and `execute.toml` is explicitly
documented as ambient authority for trusted local justfiles rather than a
sandbox.

Candidate archives contain exactly one platform executable plus license,
notice, README, security policy, changelog, checksum manifest, SBOM and
provenance. The verifier binds the archive name and digest, build record,
version, platform, Git commit, wasm asset/sidecar, dependency set, package URLs,
builder identity and exact MoonBit/MoonX toolchain. Every platform runner
executes version, query, and recipe corpora from the extracted candidate rather
than from an unrelated worktree build. Negative tests independently
tamper with the archive sidecar, build record, wasm sidecar, archive path,
symbolic-link entry, case-insensitive collision, nested member, embedded
checksum manifest, Native or wasm provenance, and removed or duplicated SBOM
components; all twelve are rejected.

Archives use normalized timestamps, owners and modes. Candidate builds force
`SOURCE_DATE_EPOCH=0` and `ZERO_AR_DATE=1`; two cache-disabled clean Native and
wasm builds from one fixed source/target path are byte-identical. The current
Native toolchain embeds target-path information, so the project does not claim
path-independent Native bytes. Instead, independent source-package rebuilds
must pass exact version, query and execution corpora.

## Supply chain and upgrade

Every Native candidate and the wasm1 MoonX asset carry a CycloneDX 1.5 SBOM
and an in-toto statement with a SLSA v1 predicate. The local verifier checks
the artifact digest,
resolved Mooncakes package URLs, commit, target, version, builder, deterministic
build parameters and exact toolchain. The manually dispatched candidate
workflow uses pinned action commits and GitHub OIDC to attest temporary CI
artifacts. It has read-only repository contents permission, contains no registry
credential and has no publishing step.

No RC exists before Phase 12. The upgrade rehearsal therefore builds the
immutable Phase 10 evidence commit `fedf99f7a6a5f99e2b559b07931d009e162fbfce`
in a separate source tree with caches disabled. It installs that executable,
runs version/query/execution corpus, replaces it with the Phase 11 candidate,
requires exact corpus parity, then restores and verifies the exact previous
bytes and corpus again.

## Current evidence

The local Phase 11 gate passes metadata, dependency/license, source-package,
cache-disabled rebuild, repeatability, four policy modes, artifact/SBOM/
provenance, tamper rejection, MoonX staging and upgrade/rollback checks. The
executable API guide adds three tests; the complete matrices pass 303 Native
and 298 wasm1 tests, and all stable backends type-check.
Both successful PR CI runs and the mandatory second audit are complete. The
candidate attestation workflow, merge and protected-main CI remain explicit
exit prerequisites and are not yet recorded as complete.
