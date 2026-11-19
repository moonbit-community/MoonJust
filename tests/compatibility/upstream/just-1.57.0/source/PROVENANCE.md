# just 1.57.0 Contract Sources

This directory vendors the `src/` and `tests/` trees, `README.md` and all seven
files under `examples/` from official just tag
`1.57.0`, commit `e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f`.

The Rust files supply source anchors for the spec index and differential
manifest. The document runner extracts the README's just fences and passes
them and the example files to the two CLIs with `--dump`. The changelog check
uses the live official executable and the SHA-256 of this commit's
`CHANGELOG.md`.

The upstream work is distributed under CC0 1.0 Universal. See `LICENSE`.
