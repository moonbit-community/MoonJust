# ADR-0005: Errors and exit status

- Status: Accepted
- Date: 2026-08-04

## Context

Compatibility requires distinguishing CLI misuse, source loading, compilation,
invocation, evaluation, host denial, recipe exit, and signal termination.
Formatting strings deep in the implementation would couple behavior to one
renderer and make JSON diagnostics impractical.

## Decision

- Error families are typed by stage: CLI, load, lex, parse, compile,
  invocation, evaluation, planning, host, execution, and capability.
- Diagnostics carry a stable code, severity, primary span, secondary labels,
  notes, help, and source chain.
- Diagnostic IR contains no ANSI escapes and no pre-rendered absolute paths.
- The CLI composition root maps typed outcomes to stdout, stderr, and exit
  status.
- Upstream exit behavior is the oracle. Until mapped, a new error kind cannot
  guess an exit code.
- Unsupported command-line behavior is explicit and uses the same usage-error
  class as the approved compatibility mapping.
- Recipe exit and signal results remain distinct from MoonJust internal errors.

## Consequences

Core packages can be tested structurally while text rendering is tested with
goldens. Future JSON diagnostics do not change parser errors. Differential tests
must compare output streams and exit status separately.
