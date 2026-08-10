# Phase 8 Security Audit

Date: 2026-08-10

## Command construction

- Every ordinary process is a `CommandSpec`; shell program and arguments stay
  separate from command text. Environment, cwd and all stdio policies are
  explicit and fake-host assertable.
- Debug implementations report command structure and environment keys only;
  captured bytes, stdin, and environment values are never rendered.
- Shell arguments are passed exactly as configured. Unix `shell()` positional
  arguments use the shell's `$0` contract; cmd/PowerShell omit the Unix shell
  name as required by their invocation model.

## Temporary scripts

- Names are generated from a recipe stem plus cryptographic/host random suffix;
  separators are rejected and the required extension remains final.
- Native creation is exclusive. Wasm creation uses `async/fs` `CreateNew` with
  policy authorization and mode `0600` or `0700` for shebang execution.
- Cleanup is registered in a structured task-group defer protected from cancel,
  and is also attempted after materialization/specification/host failures.
- Dry-run evaluates a redacted textual representation and never creates a file.

## Process and policy

- Native and wasm process adapters pass exact cwd/env/stdin and capture streams
  internally before publishing inherited output. Negative statuses map to typed
  signals; cancellation delegates to async/process group termination and reap.
- `policies/inspect.toml` remains deny-write/deny-spawn. `policies/execute.toml`
  explicitly grants env, filesystem, and process capabilities; no execution
  capability is inferred from inspect mode.

## Residual scope

Parallel scheduling, cache persistence, full Windows signal/job-object parity,
interactive terminal streaming, and resource backpressure remain Phase 9/10
work as stated by the project plan. PR #37 remote CI passed Quality gates and
all three Native smoke jobs after the Phase 8 implementation push.
