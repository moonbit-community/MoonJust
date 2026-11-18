# Contributing to MoonJust

MoonJust is a binary-only MoonBit project. Production implementation lives in
`internal/`; the root package is the executable entrypoint.

## Local checks

```text
moon update
moon info
moon fmt
moon check --target wasm --deny-warn
moon test --target wasm
moon build --release --target wasm .
moon test --target native
moon run tests/wasm_contract.mbtx   # Linux or macOS
```

Behavior changes require focused MoonBit tests. Cross-platform or compatibility
changes should be exercised with the runners in `tests`. Tests compare
observable output, status, filesystem effects, environment, stdin behavior,
and host policy; they do not assert package names, file layout, or source
implementation details.

For official compatibility, install `just 1.57.0` and run the live-oracle
command documented in `tests/compatibility/README.md`. Add a real fixture,
expected result, and upstream source anchor for each new upstream case. Do not
use a test name to synthesize an unrelated justfile, and do not use an
unbounded regex when a deterministic byte comparison is possible. Date/time
outputs must be normalized or regenerated deliberately; stale snapshots are
not compatibility evidence.

Only two workflows run on PRs and pushes to main (and in the merge queue):
- **Check, build and test** checks formatting, interfaces, the production source boundary and Wasm compilation on Linux. It runs the native test-tool tests and tests the release CLI with child processes denied: executable lookup, symlink cycles, permission-preserving format refusal and no-clobber initialization.
- **Upstream differential** builds one release Wasm and runs it on Linux, macOS and Windows against just 1.57.0. The complete Wasm package test suite runs once per host inside the strict runner; its outline ties executed specifications to upstream identities. The required `just 1.57 differential` check fails if a host or its evidence is missing.

Performance is local only: see the [paired Wasm benchmark instructions](docs/maintenance/WASM_MIGRATION.md). For published versions, manually run [MoonX verification](docs/release/MOONX_RELEASE_GATE.md).

Keep the phase boundaries explicit: project loading returns a snapshot,
planning returns an execution plan, and runtime executes only that plan.
