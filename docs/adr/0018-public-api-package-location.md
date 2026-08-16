# ADR-0018: Public API package location

- Status: Accepted
- Date: 2026-08-16

## Context

ADR-0006 placed the stable library facade in the module root. That made source,
package configuration, tests, and generated interfaces appear beside module
metadata and repository-level documentation. MoonJust is still pre-beta, so the
package path can be corrected before the public API is frozen.

## Decision

- Move the stable facade and build metadata to the `api/` package.
- Publish the facade as `moonbit-community/MoonJust/api`.
- Keep the existing functions and behavior unchanged.
- Do not retain a root compatibility package because that would preserve the
  root-level files this change removes.

This supersedes only the root-package location in ADR-0006. Its API review,
encapsulation, testing, and semantic-versioning policies remain in force.

## Compatibility

Consumers must change imports from `moonbit-community/MoonJust` to
`moonbit-community/MoonJust/api`. This is an intentional pre-beta breaking
change and is recorded in the changelog.

## Consequences

The module root contains module metadata and repository documentation rather
than a MoonBit package. Public interface review moves to
`api/pkg.generated.mbti`, while the executable continues to use the same
facade functions through its updated package import.
