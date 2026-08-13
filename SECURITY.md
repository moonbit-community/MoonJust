# Security policy

## Supported versions

MoonJust is pre-release software. Security fixes currently target the `main`
branch. A supported release table will be published before 1.0.

## Reporting a vulnerability

Do not open a public issue for a suspected command-injection, path-escape,
secret-disclosure, cache-poisoning, or process-isolation vulnerability. Use
GitHub's private vulnerability reporting for this repository. If that feature
is unavailable, contact a repository owner privately before disclosure.

Include the MoonJust commit, target, OS/architecture, minimal justfile, command,
and observed side effects. Remove credentials and unrelated environment data.

## Execution boundary

A justfile is executable code. MoonJust's Wasm target relies on host-provided
filesystem and process capabilities. Allowing process spawning does not imply
that spawned processes are contained by the parent `moonrun` policy. Review
untrusted justfiles and use an operating-system or container sandbox when
isolation is required.

The policy examples are described in [`docs/RELEASE_POLICY.md`](docs/RELEASE_POLICY.md).
In particular, `policies/execute.toml` grants ambient filesystem, environment,
and child-process access. A spawned process is not sandboxed by the parent
`moonrun` policy.

## Release integrity

Official release bundles contain SHA-256 checksums, a CycloneDX SBOM and a
provenance statement binding the artifact to its source commit and MoonBit
toolchain. GitHub release-candidate artifacts are attested by the candidate
workflow using its OIDC identity. Formal publication remains a maintainer-only
action. Verify the checksum before execution and the attestation against
`moonbit-community/MoonJust`; do not trust an archive whose provenance commit
is absent from this repository.
