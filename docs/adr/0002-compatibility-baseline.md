# ADR-0002: Compatibility baseline

- Status: Accepted
- Date: 2026-08-04

## Context

Tracking the upstream default branch while building a new implementation would
make acceptance criteria unstable. Rust implementation details are not a useful
public compatibility surface for MoonBit users.

## Decision

- The first release baseline is `just 1.57.0`, exact commit
  `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`.
- Compatibility means equivalent user-observable language, CLI, output, exit,
  side-effect, scheduling, and platform behavior.
- The upstream Rust library API and internal module structure are not
  compatibility surfaces.
- Tier A, B, W, and X classifications in `docs/PROJECT_PLAN.md` control release
  gates.
- Shell completion generation and completion scripts are Tier X.
- Every upstream test registration is mapped to evidence or an explicit reason
  that it does not apply.
- MoonJust versions follow their own SemVer and expose the upstream baseline as
  metadata.

## Consequences

Upstream releases are monitored but do not move the baseline automatically. A
baseline upgrade begins with inventory and differential changes, then updates
implementation. Known differences receive stable `MJ-COMPAT-*` identifiers;
unsupported flags are never silently ignored.
