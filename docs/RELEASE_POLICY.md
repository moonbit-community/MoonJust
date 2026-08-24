# Release policy

MoonJust prepares two related release candidates from the same reviewed commit:

- the `ZSeanYves/MoonJust` source module for Mooncakes;
- prebuilt `cmd/just` executables for Linux, macOS, Windows and wasm1.

The reviewed Native candidate matrix is Linux x86_64, macOS arm64 and Windows
x86_64. macOS x86_64 is not claimed: the official MoonBit installer removed
Intel macOS toolchain distribution before this candidate was prepared. It must
not be restored to the matrix until an official supported toolchain is
available and the real-runner gate passes.

The source module version in `moon.mod`, the application version reported by
`just --version`, and every artifact provenance statement are reviewed
together. The candidate workflow refuses a dirty tree, an unclassified
compatibility row, or a missing checksum. If the maintainer later creates a
tag, its version must match these reviewed values.

## Mooncakes and MoonX

The executable coordinate is:

```text
ZSeanYves/MoonJust/cmd/just@<version>
```

`moonx` defaults to the linear-memory wasm backend and downloads these exact
registry assets before invoking `moonrun`:

```text
/assets/ZSeanYves/MoonJust@<version>/cmd/just/just.wasm
/assets/ZSeanYves/MoonJust@<version>/cmd/just/just.wasm.sha256
```

It validates the SHA-256 sidecar before execution. A source package without
the wasm asset is therefore not a complete MoonX release. `moon package`
validates the source archive locally; publishing to the organization namespace
requires organization-owned Mooncakes credentials. Formal publication, release
tag creation and GitHub Release creation are maintainer-only actions and are
deliberately absent from repository automation. The release-candidate workflow
contains no publishing credentials or publishing command. Before handoff, its
local staging registry uses a fresh MoonX asset cache and the pinned coordinate
to run `--version` and reject a corrupt checksum.

## Wasm policies

Supplying `moonrun --policy` enables deny-by-default host access. Policy files
in this repository have intentionally different purposes:

| Policy | Filesystem | Environment | Process | Intended use |
| --- | --- | --- | --- | --- |
| `deny.toml` | none | none | denied | prove that ambient access is not inherited |
| `inspect.toml` | repository read roots | none | denied | parse, check and query trusted local inputs |
| `ci.toml` | repository read plus `_build` write | none | allowed | deterministic CI execution corpus |
| `execute.toml` | all | all | allowed | explicit local execution of trusted justfiles |

`execute.toml` is an allow-all example, not a sandbox. Spawned child processes
receive the host user's ambient authority and are not contained by the parent
Moon policy. Do not use it for untrusted justfiles.

## Artifacts and verification

Each platform archive contains one executable, `LICENSE`, `NOTICE`,
`README.mbt.md`, `SECURITY.md`, `CHANGELOG.md`, a CycloneDX SBOM, provenance,
and a checksum manifest. The wasm1 MoonX asset has its own checksum, CycloneDX
SBOM, and provenance alongside the `.wasm` file. Archives are built from a
clean checkout with release mode and stripped debug information. The
verification gate rejects:

- absolute or parent-traversing archive paths;
- duplicate archive entries or unexpected executable names;
- an artifact digest absent from the checksum manifest;
- an SBOM dependency that differs from `moon.mod`;
- provenance whose commit, repository, target or toolchain differs from the
  build inputs;
- a version line or compatibility baseline that differs from the source.

GitHub's artifact attestation action signs the temporary candidate bundles and
checksum manifest using the workflow OIDC identity. A maintainer who chooses to
publish later must verify that the selected bytes match these reviewed
candidates. Consumers should verify both the SHA-256 manifest and the GitHub
attestation against this repository.

## Upgrade and rollback

The upgrade rehearsal uses a checksum-pinned previous candidate. It builds that
immutable commit in a separate source tree, verifies it, replaces it with the
current candidate archive, runs
the query corpus, then restores the exact previous bytes and verifies them
again. The release gate also rebuilds the candidate from the source package
with independently copied exact dependency sources and global dependency and
build caches disabled, then executes both query and recipe corpora. Candidate
builds set `SOURCE_DATE_EPOCH=0` and `ZERO_AR_DATE=1`. Two clean builds from one
fixed source/target path must be byte-identical; the policy does not claim
path-independent Native binaries because the current toolchain embeds
build-path information. The
previous archive is retained until the maintainer has completed any chosen
post-publish MoonX and platform smoke tests.

If a release must be withdrawn, stop distribution of the affected assets,
publish a security notice when applicable, restore the last verified executable
from its checksum-pinned archive, and release a new SemVer version. Published
Mooncakes versions and Git tags are immutable and must not be overwritten.
