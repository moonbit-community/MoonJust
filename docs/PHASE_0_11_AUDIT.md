# Phase 0-11 strict exit audit

- Review date: 2026-08-13
- Reviewed implementation baseline: `09ac48c0a00dbf572e2d6242574da820446544f2`
- Delivery: [PR #43](https://github.com/moonbit-community/MoonJust/pull/43),
  squash commit `b4b318c981a4b81a681afb6a4a00418d70cd046a`
- First successful PR CI:
  [31667796269](https://github.com/moonbit-community/MoonJust/actions/runs/31667796269)
- Second-review PR CI:
  [31669564990](https://github.com/moonbit-community/MoonJust/actions/runs/31669564990)
- Candidate-remediation PRs: [#44](https://github.com/moonbit-community/MoonJust/pull/44),
  [#45](https://github.com/moonbit-community/MoonJust/pull/45) and
  [#46](https://github.com/moonbit-community/MoonJust/pull/46)
- Remediated implementation protected-main CI:
  [31677969665](https://github.com/moonbit-community/MoonJust/actions/runs/31677969665)
- Audit-closure baseline: `ec960b5a1cdf8bce63fcaae79f63b4f9947490f3`;
  protected-main CI
  [31697473589](https://github.com/moonbit-community/MoonJust/actions/runs/31697473589)
- Successful candidate workflow:
  [31698189163](https://github.com/moonbit-community/MoonJust/actions/runs/31698189163)
- Accepted specification: [`PROJECT_PLAN.md`](PROJECT_PLAN.md)
- Phase 11 detail: [`PHASE_11_REPORT.md`](PHASE_11_REPORT.md)

## Current verdict

Phase 0-10 remain complete under their merged evidence. Phase 11's first
successful PR CI passed, the required second review found and remediated
candidate-integrity gaps, and subsequent real candidate runs found and closed
cold-runner dependency and unsupported-platform assumptions. All four delivery
and remediation PRs merged through required checks. The final protected-main
CI and manually dispatched candidate workflow passed every supported artifact
job. Phase 11 therefore satisfies every declared exit condition. No formal
publication, tag or GitHub Release was performed.

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

The post-merge candidate rehearsal then supplied two further clean-runner
findings before exit was accepted:

- the source-validation job installed exact dependencies before its frozen
  rebuild, but each isolated artifact runner attempted a frozen build after
  registry refresh alone; every artifact job now installs the exact resolved
  graph before entering frozen mode, and the shared gate proves the same cold
  bootstrap path;
- the official MoonBit installer no longer distributes an Intel macOS
  toolchain. In accordance with the plan's real-runner rule, the supported
  matrix was narrowed before RC to Linux x86_64, macOS arm64 and Windows
  x86_64 instead of substituting an emulated result. macOS x86_64 can return
  only after official support and a real-runner gate.

The audit also moved artifact upload actions to their pinned Node 24 release,
removing the clean-runner deprecation warning without changing candidate
contents. Failed discovery runs
[31672990008](https://github.com/moonbit-community/MoonJust/actions/runs/31672990008)
and
[31674990173](https://github.com/moonbit-community/MoonJust/actions/runs/31674990173)
are retained as evidence rather than hidden; PRs #44 through #46 close the
identified causes.

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
| Candidate remediations | PRs #44-#46 passed checks and merged as `9e85f81`, `ab22da4` and `09ac48c` |
| Supported candidate workflow | run 31698189163 on audit-closure baseline `ec960b5a` passed source validation, three Native artifacts, wasm1 asset and OIDC attestations |
| Delivery merge | PR #43 merged as `b4b318c981a4b81a681afb6a4a00418d70cd046a` |
| Remediated implementation CI | run 31677969665 passed quality, Ubuntu, macOS and Windows |
| Audit-closure protected-main CI | run 31697473589 passed quality, Ubuntu, macOS and Windows on `ec960b5a` |

## Publication boundary

Repository automation prepares, validates, temporarily uploads and attests
release candidates only. It has no Mooncakes credential, `moon publish`, tag
creation or push, GitHub Release creation, or repository contents write
permission. Formal publication remains exclusively a maintainer action.

## Exit condition

No review or clean-runner finding remains open. The delivery and remediation
PRs passed required checks and merged; protected `main` passed the complete CI
matrix; and the manual release-candidate workflow proved all supported Native
candidates plus the wasm1 asset and OIDC attestations without publishing.
Phase 11 is complete.
