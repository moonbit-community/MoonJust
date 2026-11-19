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

For official compatibility, install `just 1.59.0` and run the live-oracle
command documented in `tests/compatibility/README.md`. Add a real fixture,
expected result, and upstream source anchor for each new upstream case. Do not
use a test name to synthesize an unrelated justfile, and do not use an
unbounded regex when a deterministic byte comparison is possible. Date/time
outputs must be normalized or regenerated deliberately; stale snapshots are
not compatibility evidence.

Only two workflows run on PRs and pushes to main (and in the merge queue):
- **Check, build and test** checks formatting, interfaces, the production source boundary and Wasm compilation on Linux. It runs the native test-tool tests and tests the release CLI with child processes denied: executable lookup, symlink cycles, permission-preserving format refusal and no-clobber initialization.
- **Upstream differential** builds one release Wasm and runs it on Linux, macOS and Windows against just 1.59.0. Each host runs the live CLI fixtures and document contracts. A passing Wasm suite and a matching outline entry establish execution of an indexed local assertion. Give a local smoke test a fifth spec-index field describing the subset it checks. The aggregate check verifies each host's evidence. Its legacy GitHub check name is required by branch protection. [Report schema and categories](tests/compatibility/README.md#reading-a-coverage-report)

Run performance benchmarks locally using the [paired Wasm benchmarks](tests/benchmark/PR80_EVIDENCE.md#reproduction). After publishing, run the [MoonX release verification workflow](.github/workflows/moonx-release.yml) from the revision that declares the published version.

Keep the phase boundaries explicit: project loading returns a snapshot,
planning returns an execution plan, and runtime executes only that plan.
