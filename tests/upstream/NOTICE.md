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

Future copied or adapted fixtures must append a row:

| MoonJust path | Upstream path | Modification | Compatibility ID |
| --- | --- | --- | --- |
| `src/lexer/upstream_lexer_test.mbt` | `src/lexer.rs` (`lexer::tests`) | Adapted key token/error cases to byte-span MoonBit black-box tests; omitted Rust-internal `presume_error` | `MJ-LEX-ORACLE-1.57.0` |

No upstream implementation source has been copied into MoonJust during Phase 0.
