# ADR-0016: Phase 7 CLI environment composition

- Status: Accepted
- Date: 2026-08-08

## Context

Recipe execution needs a deterministic configuration before Phase 8 may create
processes. `just 1.57.0` combines command-line variable overrides, shell
selection, temporary-directory selection, platform behavior, dotenv entries,
exports, exported recipe parameters, unexports, and recipe `[env]` attributes.
These are distinct domains: `--set` changes Just variables, while the other
layers determine a child process environment.

Core argparse consumes one value per option, but upstream `--set` consumes two.
Shell arguments also have ordered replacement semantics: the last occurrence
of `--clear-shell-args` or `--shell-arg` determines the effective list.

## Decision

- CLI scanning captures every global `--set NAME VALUE` pair before argparse,
  encodes only an opaque index for parser validation, and leaves identically
  named recipe options untouched after invocation begins.
- `CliArguments` exposes ordered variable override pairs and a three-state
  shell argument override: absent, present with values, or explicitly empty.
  It has no derived debug representation because override values may be
  secrets.
- `environment.OverrideTable` validates module-qualified identifiers and uses
  deterministic last-wins semantics without deriving `Debug`.
- `PlatformConfiguration` consumes explicit `HostPlatform` facts. Environment
  name matching is case-sensitive except on Windows, where it is ASCII
  insensitive.
- Shell resolution follows the upstream table: CLI program/arguments, Windows
  shell settings, ordinary shell setting, then `sh -cu`. CLI arguments without
  a CLI program select `sh` on every platform.
- A CLI tempdir wins over the evaluated setting. Both resolve lexically from
  the project working directory; absence delegates to the host runtime or OS
  default.
- Process environments compose in this order: ambient, already-filtered
  dotenv, exported variables, unexports, exported recipe parameters, and
  recipe `[env]` attributes.

## Consequences

Phase 8 receives a pure `EnvironmentConfiguration` and does not need to infer
platform behavior or repeat precedence logic while constructing commands.
Values remain accessible only through deliberate accessors and are not present
in structural errors or debugging output.

The unit suite covers every precedence row on Native and wasm1. A seven-case
differential gate executes the pinned upstream binary for `--set`, ordered
shell overrides, tempdir placement, and complete child-environment precedence.
