# Compatibility Corpus

The runner in `tests/compat` is the executable compatibility contract. It
starts MoonJust and the pinned just 1.57.0 oracle in isolated temporary roots
and compares status, stdout, stderr, merged output, filesystem effects, and
live-output observations byte-for-byte where the case declares them.

Each case must have a manifest entry, a matching `compat-id`, and an explicit
`match` or `difference` expectation. Differences are accepted only when the
manifest names a specific reason and the runner observes only the fields
allowed by that reason. Upstream anchors are checked against the pinned
just 1.57.0 test inventory.

The files under `upstream/` are provenance and oracle metadata. They do not
replace executable behavior tests and are never treated as a source of
implementation code.
