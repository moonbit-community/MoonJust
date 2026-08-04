# ADR-0001: Product and command name

- Status: Accepted
- Date: 2026-08-04

## Context

The implementation needs a distinct project identity while remaining usable as
a `just`-compatible command. Multiple command entry points would create drift,
especially for argv[0], `just_executable()`, help, and release packaging.

## Decision

- The product and module are named **MoonJust**.
- The MoonBit module is `moonbit-community/MoonJust`.
- The only executable package is `cmd/just`.
- The intended Mooncakes coordinate is
  `moonbit-community/MoonJust/cmd/just`.
- Native release artifacts expose the executable name `just` when used as a
  compatibility replacement.
- Documentation always identifies the project as an independent
  implementation and does not imply upstream endorsement.

## Consequences

There is no parallel `cmd/moonjust` implementation. Packaging may provide a
`moonjust` alias only if it resolves to the exact same artifact. Tests must not
hard-code a development build path where upstream behavior expects the actual
executable path.
