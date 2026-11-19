# Compatibility corpus

MoonJust tests its release Wasm CLI against official just 1.59.0. The inventory
contains 2,461 upstream test identities. One fixture can supply evidence for
several identities, and one identity can require hundreds of CLI invocations.
The inventory counts identities. Use each row's `fixture`, `upstream_source_anchor`,
`status` and `execution_state` to interpret a result.

## Reading a coverage report

Schema 4 assigns every identity a row. The numbers below are declarations in
the pinned inventory. The per-host report records which checks actually ran.

| Status | Identities | What the evidence establishes |
| --- | ---: | --- |
| `differential-exact` | 1,443 | On a successful row, the Wasm CLI and live official CLI matched on all observations declared by the fixture after its permitted normalizations. |
| `differential-known-difference` | 3 | The oracle successfully reformatted the file. The Wasm CLI exited 1 with empty stdout, the reviewed diagnostic bytes and its initial tree intact. An unexpected match fails the fixture. |
| `moonbit-spec` | 906 | The Wasm package suite passed and its outline contained the indexed local test at its exact declaration. The test body defines which behavior was asserted. This category makes no claim that every upstream assertion was ported. |
| `local-smoke` | 4 | Three assertions check selected parser fields. One checks the MoonJust-specific `Unsupported("--completions")` error for `--list --completions`. The upstream clap test requires a parse error. Each row describes its assertion in `evidence_scope`. |
| `document-oracle` | 3 | The two CLIs ran the upstream document checks described below. The required observation differs by document. |
| `repository-only` | 3 | Two upstream README heading rules and the generated README constants table concern just's repository. Their execution state is `excluded`. |
| `excluded-completion` | 39 | Shell completion generation and its protocol are outside the portable CLI contract. |
| `excluded-signal` | 21 | Raw signal identity and forwarding are outside the portable CLI contract. |
| `host-limited` | 1 | On Linux an invalid byte in the invocation directory can abort moonrun during its current-directory request. The report records this identity as deferred. [Reproduction and controls](upgrade/host-limits.md) |
| `unclassified` | 0 required | Strict mode fails for an identity without an evidence category. A source snapshot alone cannot establish execution. |

`status` describes the expected evidence. `execution_state` records
`executed`, `failed`, `unexecuted`, `excluded`, `deferred-host` or `deferred-platform`.
For differential rows, `differential_executed` counts attempted comparisons,
including mismatches. `differential_exact` and `differential_known_difference`
in the summary count successful comparisons of each kind. Local spec, smoke
and document execution totals require a successful check. A zero exit from
the strict runner also requires the fixture, index and oracle validation to pass.

`--help` and `--version` have separate product-identity fixtures and pinned
candidate stdout digests. `product_identity_difference` counts verified fixtures
outside the 2,461 upstream rows. The three in-place formatting refusals have
live oracle comparisons and check the candidate's complete original tree.
[Reviewed exceptions](../testkit/functional_allowlist.mbt)

## Document identities

- `readme::readme` extracts all 195 blocks with the exact three-backtick
  opening fence and language tag `just` from the pinned README. Each CLI must exit 0 on
  `--dump` for each block in an isolated directory. The assertion covers acceptance.
- `examples::examples` runs both CLIs with `--justfile FILE --dump` on each of
  the seven files from the upstream examples directory and requires exit 0 for
  every invocation. The dumped text is outside this upstream assertion.
- `changelog::print_changelog` compares the complete `--changelog` stdout with
  the live official CLI, verifies the oracle against the SHA-256 of the pinned
  upstream `CHANGELOG.md`, and requires both processes to exit 0 with empty stderr.

The upstream `man::output` identity uses a normal differential fixture.
MoonJust also has local byte-level tests for its static changelog and manual
responses. The upstream document inputs and original Rust assertions are
available offline. [Pinned inputs](upstream/just-1.59.0/source)

## Fixtures and anchors

The runner starts each side of a differential fixture in its own temporary
root. Every fixture declares its observations in the manifest. They include
status, stdout and stderr, with tree contents, merged output, live output and
step-by-step results where applicable. Rows record required platforms and
fixture-supplied host inputs such as architecture, CPU count or the re-entry
launcher. A passing injected case establishes behavior with those inputs.

Every fixture has a manifest entry, matching `compat-id`, an explicit
`match` or `difference` expectation and recorded oracle output. A normal
run uses the live pinned executable. `--record-expected` writes snapshots,
and `--verify-snapshots` checks them against a live run on the same platform.
Regex expectation files fail validation. UUID normalization accepts a complete
lowercase v4 UUID with an RFC variant. The parallel fixtures allow only
permutations of complete serialized jobs or of sibling recipes between their
shared dependency and dependent. Both rules apply solely to declared stdout.
The timestamp fixtures normalize one command's clock prefix. Multi-command
traces retain every clock reading and the order of the commands.

The spec index has four tab-separated fields giving the upstream identity,
local declaration or provenance location, local test name when present,
and upstream source anchor. A fifth field documents a local smoke assertion's
scope. Excluded identities can reference their pinned Rust declaration directly.
Strict mode runs the Wasm test suite and verifies declaration locations
and names against `moon test --outline`. [Spec index](upstream/just-1.59.0/spec-index.txt)

## Run locally

~~~sh
moon build --release --target wasm .
moon build --release --target native ./tests/wasm_reentry
moon run --target native ./tests/compat -- \
  --candidate _build/wasm/release/build/MoonJust.wasm --candidate-runner moonrun \
  --wasm-reentry _build/native/release/build/tests/wasm_reentry/wasm_reentry.exe \
  --official just --execution-target wasm --strict-coverage --allow-deferred-platform \
  --coverage-report _build/coverage-wasm.json
~~~

Use `--case DIRECTORY` to run one differential fixture or `--case readme::readme`,
`--case examples::examples` or `--case changelog::print_changelog` to run one
document identity. Omit `--strict-coverage` for a partial run.

Fixtures with host-specific behavior run on their declared platforms. The flag
`--allow-deferred-platform` permits this in a single-host run. The aggregate
requires schema 4 reports from Linux, macOS and Windows for the same Wasm
target, with every required row executed on its applicable hosts.
