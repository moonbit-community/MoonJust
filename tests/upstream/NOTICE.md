# Upstream test provenance

The compatibility oracle and fixture source is:

- Project: `casey/just`
- Repository: <https://github.com/casey/just>
- Tag: `1.57.0`
- Commit: `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`
- License: CC0-1.0
- Release date: 2026-07-19

`just-1.57.0/test-list.txt` is a mechanically generated list of test
registrations emitted by `cargo test -- --list`. It contains names only and no
test implementation.

The recorded differential oracles are platform-specific because the pinned
Rust test suite has conditional registrations. `harness-results.jsonl` is the
Darwin/aarch64 audit snapshot, `harness-results-linux.jsonl` is the
Linux/x86_64 snapshot, and `harness-results-windows.jsonl` is the
Windows/x86_64 snapshot. The Linux snapshot includes the two Linux-only
non-Unicode host tests and omits the BSD/macOS-only SIGINFO registration. The
harness selects the matching snapshot and rejects cross-platform or mixed-host
oracle files before comparing result rows.

The Linux wasm oracle records two explicit `not-applicable` rows for the
non-Unicode host tests. MoonJust Native passes those upstream tests; the shared
MoonX/`moonrun` host currently panics while handling the invalid host value, so
the wasm rows are retained as a named host limitation rather than normalized to
`exact`. The limitation is documented in
[`docs/reports/PLATFORM_COMPATIBILITY.md`](../../docs/reports/PLATFORM_COMPATIBILITY.md).

Future copied or adapted fixtures must append a row:

| MoonJust path | Upstream path | Modification | Compatibility ID |
| --- | --- | --- | --- |
| `internal/lexer/upstream_lexer_test.mbt` | `src/lexer.rs` (`lexer::tests`) | Adapted key token/error cases to byte-span MoonBit black-box tests; omitted Rust-internal `presume_error` | `MJ-LEX-ORACLE-1.57.0` |
| `internal/parser/corpus_test.mbt` | `src/parser.rs`, `src/attribute.rs` | Adapted stable grammar inventory, attribute argument ranges, error locations, and recovery cases to MoonBit AST tests | `MJ-PARSE-ORACLE-1.57.0` |
| `internal/formatter/formatter_test.mbt` | `src/formatter.rs`, `src/parser.rs` | Adapted representative canonical/idempotence cases without copying Rust AST internals | `MJ-FMT-ORACLE-1.57.0` |
| `internal/formatter/markdown_test.mbt` | `src/tangle.rs` | Adapted fenced block, info string, ignored block, source-offset, and budget boundaries | `MJ-TANGLE-ORACLE-1.57.0` |
| `internal/semantic/semantic_test.mbt`, `internal/loader/loader_test.mbt` | `src/settings.rs`, `src/attribute.rs`, `src/analyzer.rs`, `src/search.rs`, `src/loader.rs`, `src/module.rs` | Adapted setting/attribute inventories, static checks, discovery, graph, and source-chain cases to capability-backed MoonBit tests | `MJ-SEM-LOAD-ORACLE-1.57.0` |
| `internal/builtin/builtin_test.mbt`, `internal/evaluator/evaluator_test.mbt` | `src/evaluator.rs`, `src/value.rs`, `src/function.rs`, `src/function/semver.rs`, `src/function/sha256.rs` | Adapted value, scope, builtin registry, SemVer/regexp, hash, effect, and budget cases without copying Rust implementation | `MJ-EVAL-BUILTIN-ORACLE-1.57.0` |

No upstream implementation source was copied into MoonJust during initial development.
