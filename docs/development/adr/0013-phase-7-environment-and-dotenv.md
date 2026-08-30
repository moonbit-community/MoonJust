# ADR-0013: Phase 7 environment and dotenv

- Status: Accepted
- Date: 2026-08-07

## Context

`just 1.57.0` parses environment files through `dotenvy 0.15.7`, but its
observable behavior also includes file discovery, explicit path precedence,
multiple-file merging, ambient environment precedence, required mode, and
command-produced dotenv data. Environment values may contain credentials, so
ordinary derived debugging and value-bearing parse errors are unsafe.

The evaluator already owns a lexical variable environment. Dotenv values are
process environment data and need a separate type so the two domains cannot be
mixed accidentally.

## Decision

- `environment.EnvTable` is the deterministic process-environment snapshot.
  It intentionally has no `Debug` derivation. Name lookup is explicitly either
  case-sensitive or ASCII-insensitive so Windows composition can preserve host
  precedence without changing spelling on Unix.
- `HostEnv.env_entries` supplies an explicit snapshot. Native implements the
  capability, `FakeHost` supplies deterministic values, and the Phase 6 wasm
  inspection adapter does not expose it.
- The in-project parser follows the exact `dotenvy::from_read_iter` path used
  by pinned `just`, including quoting, escapes, multiline values, comments,
  substitutions, CRLF, duplicate keys, and BOM rejection.
- Parse errors retain only line and column. Host failures are reduced to
  capability/source categories, and command failures retain only source index
  and exit status. Errors never retain dotenv values, child stderr, argv,
  environment entries, or a command string, including in structural debug
  output.
- Explicit dotenv paths are tried first. Any explicit path hit stops filename
  search. Filename search walks ancestors and merges every configured filename
  in the first directory with a hit. Later sources win.
- Ambient environment wins unless override is enabled. Command sources use the
  same parser, merge in order, run in the working directory, and are skipped
  during dry runs. Their exit status is preserved.
- `dotenv-command` may compose with `dotenv-override`; it conflicts with
  filename/path settings and enabled load/required settings, matching upstream.

## Consequences

CLI composition can consume `EnvTable` in PR-074 without reading process-global
state in semantic or evaluator packages. The parser has an executable
differential gate against the exact dotenvy version, and invalid fixtures also
assert that candidate diagnostics do not disclose values.

The Rust oracle is test-only and locked independently. It is not linked into
MoonJust or shipped with the CLI.
