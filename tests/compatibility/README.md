# Compatibility Corpus

The runner in `tests/compat` is the executable compatibility contract. It
starts MoonJust and the pinned just 1.57.0 oracle in isolated temporary roots
and compares status, stdout, stderr, merged output, filesystem effects, and
live-output observations byte-for-byte where the case declares them.

Each case must have a manifest entry, a matching `compat-id`, and an explicit
`match` or `difference` expectation. The two product-identity cases (`--version`
and `--help`) use exact local snapshots and are outside functional upstream
differences. Functional differences are not accepted. Every upstream anchor is
checked against the pinned just 1.57.0 source tree.

The files under `upstream/` are provenance and oracle metadata. They do not
replace executable behavior tests and are never treated as a source of
implementation code.

Use `--coverage-report PATH` to emit a schema 3 JSON row for every identity in
the pinned upstream inventory. The runner uses only these statuses:
`differential-exact`, `differential-known-difference`, `moonbit-spec-exact`,
`excluded-completion`, `excluded-signal`, and `unclassified`. Supplying
`--strict-coverage` fails when any identity is unclassified, deferred, failed,
or counted without an execution record. Every executable upstream behavior must
carry a real fixture, input, expected output, exit status, and source anchor.
Internal parser, semantic, evaluator, and formatter behavior belongs in MoonBit
whitebox tests with exact token, AST, diagnostic, value, or byte assertions;
strict mode executes those tests and verifies their `moon test --outline`
locations.

Completion generation and runtime signal identity/forwarding are excluded only
for their documented shell-protocol and OS-process-group reasons. Static signal
validation, option parsing, diagnostics, and all other platform-testable
behavior remain in scope.

Cases whose upstream test is conditionally compiled for one operating system
may declare `platform = "windows"`, `"macos"`, or `"linux"` in the manifest.
The runner reports such a case as `deferred-platform` on other systems and
executes it on the matching CI runner; the aggregate coverage merge requires
the matching report rather than treating a local defer as a pass.

Pure lexical and semantic invariants are indexed in
`upstream/just-1.57.0/spec-index.txt`. Each index row points to a concrete
MoonBit assertion file or black-box fixture, together with the upstream source
line that defines the case. The source snapshot preserves the original test
body under explicit `input` and `expected` sections for provenance; it is not
used as a substitute for executable evidence. The strict report currently has
zero unclassified identities.

Use `--record-expected` once a deterministic black-box fixture is ready to
write the official status, stdout, stderr, and filesystem snapshot into the
case directory. Normal runs execute the official 1.57.0 binary as the live
oracle. `--verify-snapshots` is an optional same-platform audit of recorded
official bytes; the cross-platform CI gate uses the live oracle because shell,
environment, and filesystem diagnostics can legitimately differ by runner.
Snapshot files are not a clock-free oracle: cases that print the current date
or time use a finite, fixture-declared normalization. Regex files are forbidden
and cause strict validation to fail.

The current strict report is the source of compatibility totals. A platform
run may defer a case guarded for another operating system (currently one
Windows-only case on Unix); the runner still counts that identity in the
2,417-row inventory and the pure MoonBit merge requires its matching CI report.

For Wasm runs, pass `--candidate-runner moonrun` and build the native
`tests/wasm_reentry` helper. The helper is supplied with `--wasm-reentry` so
recipes that call `just_executable()` can re-enter the Wasm artifact through
`moonrun`; without it, those child-process cases are reported as failures.
