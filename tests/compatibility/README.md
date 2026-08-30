# Compatibility Corpus

The runner in `tests/compat` is the executable compatibility contract. It
starts MoonJust and the pinned just 1.57.0 oracle in isolated temporary roots
and compares status, stdout, stderr, merged output, filesystem effects, and
live-output observations byte-for-byte where the case declares them.

Each case must have a manifest entry, a matching `compat-id`, and an explicit
`match` or `difference` expectation. Differences are accepted only when the
manifest names a specific reason, the runner observes only the fields allowed
by that reason, and the candidate's differing byte stream matches its pinned
SHA-256 digest. Upstream anchors are checked against the pinned just 1.57.0
test inventory.

The files under `upstream/` are provenance and oracle metadata. They do not
replace executable behavior tests and are never treated as a source of
implementation code.

Use `--coverage-report PATH` to emit one JSON row for every identity in the
pinned upstream inventory. The runner uses only these statuses:
`differential-exact`, `differential-known-difference`, `moonbit-spec-exact`,
`excluded-completion`, `excluded-signal`, and `unclassified`. Supplying
`--strict-coverage` fails when any identity is unclassified; it is never
silently counted as a pass. Every executable upstream behavior must carry a
real fixture, input, expected output, exit status, and source anchor. Internal
parser, semantic, evaluator, and formatter behavior belongs in MoonBit
whitebox tests with exact token, AST, diagnostic, value, or byte assertions.

Completion generation and runtime signal identity/forwarding are excluded only
for their documented shell-protocol and OS-process-group reasons. Static signal
validation, option parsing, diagnostics, and all other platform-testable
behavior remain in scope.

Pure lexical and semantic invariants are indexed in
`upstream/just-1.57.0/spec-index.txt`. Each index row points to a concrete
MoonBit assertion file or to a source-backed block in
`upstream/just-1.57.0/upstream-fixtures.txt`, together with the upstream source
line that defines the case. Snapshot blocks preserve the original upstream
test body under explicit `input` and `expected` sections; they are audit-only
until a real MoonBit assertion is registered, and therefore remain
`unclassified` in coverage reports.

Use `--record-expected` once a deterministic black-box fixture is ready to
write the official status, stdout, stderr, and filesystem snapshot into the
case directory. Normal runs validate those snapshots before comparing the
candidate, while regex-backed upstream cases use their declared pattern for
the corresponding stream.
