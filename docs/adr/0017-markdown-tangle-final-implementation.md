# ADR-0017: Markdown tangle final implementation

- Status: Accepted
- Date: 2026-08-12
- Finalizes: ADR-0007

## Context

ADR-0007 kept `moonbit-community/cmark 0.4.4` as a conditional private
candidate. Phase 10 repeated the buy/build gate against the pinned `just
1.57.0` tangle suite and the project's byte-span requirements.

MoonJust needs only fenced `just` block selection, but it must retain one output
byte position for every source byte outside selected content. The cmark AST
reports UTF-16-oriented locations, requires a conversion index for UTF-8 byte
spans, and adds a large general-purpose Markdown tree to a narrow load path.
Neither links nor prose need semantic interpretation.

## Decision

MoonJust uses the project-owned source-aware extractor in
`internal/formatter/markdown.mbt` as the final implementation.

- Only top-level fenced blocks whose first info token is lowercase `just` are
  selected.
- Backtick and tilde fences, matching characters and minimum closing lengths
  follow the pinned upstream corpus.
- Fences inside block quotes, list containers, HTML comments, indented code and
  outer fences are excluded.
- Non-selected bytes become spaces while original line terminators and byte
  offsets remain intact.
- Markdown filenames are detected case-insensitively by the loader. Formatting
  prints canonical extracted just source and never rewrites prose in place.
- Explicit line and byte budgets remain enforced before extraction.

The acceptance gate runs all five upstream `tangle::tests` from commit
`e01a6bd7e7a30baf86bc86d2b95b0998ebbdc36f` plus MoonJust's malformed,
Unicode, CRLF, nested-container and resource-boundary tests on Native and
wasm1.

## Consequences

No cmark dependency is added to production packages, and no third-party AST or
position type enters public interfaces. MoonJust owns a deliberately narrow
CommonMark subset, so future Markdown boundary changes require a corpus case
and a new compatibility decision rather than an incidental parser tweak.
