# Phase 0-11 strict exit audit

- Review date: 2026-08-13
- Reviewed implementation baseline: `f4e96ef78cc40253a31b9e9f644af6ed9ca833f7`
- Delivery: [PR #43](https://github.com/moonbit-community/MoonJust/pull/43)
- First successful PR CI:
  [31667796269](https://github.com/moonbit-community/MoonJust/actions/runs/31667796269)
- Second-review PR CI:
  [31669564990](https://github.com/moonbit-community/MoonJust/actions/runs/31669564990)
- Accepted specification: [`PROJECT_PLAN.md`](PROJECT_PLAN.md)
- Phase 11 detail: [`PHASE_11_REPORT.md`](PHASE_11_REPORT.md)

## Current verdict

Phase 0-10 remain complete under their merged evidence. Phase 11's first
successful PR CI passed, the required second review found and remediated
candidate-integrity gaps, and the remediation CI passed quality plus Ubuntu,
macOS and Windows. The implementation and review contracts are satisfied.
The manually dispatched candidate workflow, merge and protected-main CI remain
explicit pending exit conditions; no formal publication, tag or GitHub Release
was performed.

## Phase 11 strict review

The review traced PR-110 through PR-114 from plan text to candidate bytes,
source packages, policies, local staging, supply-chain documents, negative
tests, upgrade rehearsal and CI jobs. It found and remediated the following
issues before merge:

- clean GitHub runners lacked the `moonx` entry point even though the pinned
  toolchain installed `moon`; a cross-platform bootstrap now creates and
  verifies the corresponding entry point in every isolated job;
- source packaging could carry Python/editor/cache or credential residue;
  ignore rules and the archive verifier now reject those classes;
- archive verification compared root basenames rather than the complete
  recursive member set, and did not reject case-insensitive collisions or
  extra directory/link entries;
- duplicate embedded checksum rows could be collapsed by dictionary parsing;
- SBOM dependency checks used sets, which could hide duplicate components, and
  provenance digest algorithms were not compared as exact descriptors;
- Native candidates carried local SBOM/provenance while the wasm1 MoonX asset
  relied only on its checksum and remote attestation;
- cross-platform jobs executed `--version` from extracted candidates but ran
  the deeper corpus only against worktree builds;
- resolved dependency caches contained tool-generated empty `* 2` directories
  that were silently ignored without proving they remained empty.

The corrected verifier requires an exact recursive archive inventory, one
exact checksum entry, independently reconstructed CycloneDX 1.5 and SLSA v1
objects, Native and wasm1 artifact bindings, exact source digests, no source
symlinks, and only verified-empty tool-generated duplicate directories. Every
platform candidate now executes version, query and recipe corpora after
extraction. Twelve independent tamper classes are rejected.

## Current matrix

| Evidence | Result |
| --- | --- |
| Native tests | 303 passed, 0 failed |
| wasm1 tests | 298 passed, 0 failed |
| All stable backend checks | pass |
| Source-package cold rebuild | pass with exact copied dependencies and caches disabled |
| Reproducibility | two clean fixed-path Native/wasm builds byte-identical |
| Wasm policies | explicit deny, default deny, inspect, controlled CI and full execute pass |
| Candidate archives | exact members, external/embedded checksums and extracted corpus pass |
| Supply chain | Native and wasm1 CycloneDX/SLSA documents pass exact local verification |
| Negative matrix | 12 tamper classes rejected |
| Upgrade and rollback | Phase 10 corpus parity and exact-byte rollback pass |
| First successful PR CI | run 31667796269 passed quality, Ubuntu, macOS and Windows |
| Second review | completed; candidate-integrity remediation applied in `f4e96ef` |
| Second-review PR CI | run 31669564990 passed quality, Ubuntu, macOS and Windows |
| Candidate workflow | pending after reviewed workflow reaches `main` |
| Delivery merge and protected-main CI | pending |

## Publication boundary

Repository automation prepares, validates, temporarily uploads and attests
release candidates only. It has no Mooncakes credential, `moon publish`, tag
creation or push, GitHub Release creation, or repository contents write
permission. Formal publication remains exclusively a maintainer action.

## Pending exit

No second-review finding remains open. Phase 11 becomes complete only after
the reviewed PR merges through required checks, the manual release-candidate
workflow proves all four Native candidates plus the wasm1 asset and OIDC
attestations without publishing, and the resulting protected-main CI passes.
