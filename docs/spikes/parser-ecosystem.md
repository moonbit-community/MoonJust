# Parser ecosystem qualification

- Date: 2026-08-04
- Spike module: `spikes/ecosystem`
- Required targets: Native and wasm1
- Development host: macOS 26.5.2 arm64
- Measurement toolchain: `moon 0.1.20260803`, `moonc 0.10.6+80dc50f24`

## Purpose

This spike answers the Phase 0 buy/build questions for source representation,
regular expressions, Markdown tangle, and date/time formatting. Dependencies
are pinned in a nested module so none of their APIs or transitive packages enter
MoonJust's production graph before the corresponding compatibility gate passes.

## Dependency inventory

| Candidate | Exact version | License | Transitive dependencies | Downloaded source |
| --- | --- | --- | --- | ---: |
| `moonbitlang/regexp` | 0.3.5 | Apache-2.0 | none | 584 KiB / 11,770 MoonBit lines |
| `moonbit-community/cmark` | 0.4.4 | Apache-2.0 | `myfreess/casefold 0.1.3`, `myfreess/charclass 0.1.2`, both Apache-2.0 | 2,064 KiB / 38,337 MoonBit lines |
| `moonbitlang/x/time` | 0.4.47 | Apache-2.0 | none at module level | 1,136 KiB for `x`; 5,804 MoonBit lines under `time` |

`moon tree` confirms all three direct versions. These packages remain isolated;
an implementation PR must repeat license, API, target, and differential review
before adding any of them to the root `moon.mod`.

## Contract results

The deterministic suite selects ten tests and passes on both Native and wasm1.

| Area | Native | wasm1 | Result and decision |
| --- | --- | --- | --- |
| UTF-8 source | Pass | Pass | Use core UTF-8 encode/decode and build MoonJust's byte-indexed `Source`; invalid UTF-8 remains a typed load error. |
| Regexp basic capture and Unicode category | Pass | Pass | `regexp 0.3.5` is a conditional engine candidate behind a MoonJust adapter. |
| Regexp Rust syntax boundary | Pass | Pass | Package syntax differs and is a strict superset in places; never expose `compile` directly. |
| Markdown fenced block selection | Pass | Pass | `cmark 0.4.4` can represent the upstream top-level fenced-block rules. Adopt conditionally behind a tangle adapter. |
| Markdown source location | Pass | Pass | Locations exist, but are UTF-16 code-unit positions and must be converted to UTF-8 byte spans. |
| Time value model | Pass | Pass | Fixed offsets and calendar fields are usable, but host time-zone discovery and just/chrono formatting are absent. |
| Formatter prototype | Pass | Pass | A small `%Y/%m/%d/%H/%M/%S/%z`-equivalent prototype works; the production formatter remains project-owned. |

### Source and span

MoonBit `String` indexing is not the canonical source coordinate. For
`"a\n中\r\n🙂"`, the string length is 7 code units and UTF-8 storage is 11
bytes; line starts are byte offsets `[0, 2, 7]`. The production source loader
will retain validated `Bytes`, and all AST spans remain half-open byte ranges as
required by ADR-0003.

The cmark fixture makes the incompatibility executable: after a non-ASCII
prefix, the first just code line begins at UTF-8 byte 24, while cmark reports
UTF-16 code-unit position 22. The adapter must map cmark line/position data
through MoonJust's byte line index. cmark position types cannot cross the
adapter boundary.

### Regular expressions

The candidate passes captures, cached matching, Unicode general category
`\p{L}`, malformed-pattern errors, and Native/wasm1 execution. It is not a
drop-in implementation of Rust `regex`:

- Named groups use `(?<name>...)`; the upstream-compatible
  `(?P<name>...)` form is rejected.
- Unicode script `\p{Greek}` is rejected even though it is accepted by Rust
  `regex`.
- The package accepts named backreferences such as `\k<name>`, which Rust
  `regex` rejects. Allowing this would expand both syntax and worst-case
  complexity.
- Look-around is rejected, matching the upstream engine's broad restriction.
- The public package has no replacement API matching Rust replacement
  expansion semantics.

Decision: retain `0.3.5` as a candidate engine only. PR-053 must add a syntax
validator/translator, reject unsupported supersets before compilation, own the
replacement parser, and pass a Rust-oracle corpus for syntax, Unicode, captures,
replacement, malformed input, and adversarial complexity. If those gates cannot
be met without a fragile translator, MoonJust will implement or maintain a
restricted compatible engine instead.

### Markdown tangle

The cmark AST exposes fenced layout, info strings, code lines, and locations.
The spike reproduces the selection decisions represented by upstream
`src/tangle.rs`: lower-case `just` as the first info token, backtick and tilde
fences, extra info, and unterminated fences are selectable; `justfile`, `JUST`,
indented blocks, blockquotes, list items, HTML comments, and code nested inside
another fence are excluded when only direct document blocks are considered.

Decision: use `cmark 0.4.4` as the initial private implementation candidate for
PR-036. Before production adoption, the adapter must reproduce every upstream
tangle case byte-for-byte, preserve one output line per input line, pass
CommonMark boundary and resource-budget tests, and convert all locations to
MoonJust spans. PR-104 is the final buy/build gate. Failure means replacing the
dependency with a specialized source-aware fenced-block extractor, not exposing
cmark types publicly.

### Date and time

`x/time 0.4.47` provides deterministic UTC/fixed-zone calendar arithmetic and
TZif2 parsing. It does not discover the host clock or local zone, and its own
README lists custom string formatting as future work. Pulling the full
experimental `moonbitlang/x` module into the semantic core would also be a poor
ownership boundary.

Decision: MoonJust owns the chrono-compatible format parser and renderer used
by `datetime` and `datetime_utc`. `HostClock` supplies the instant and host-zone
data. The `x/time` value model may be used privately in a time adapter only
after the upstream datetime corpus, DST cases, invalid directives, pre-epoch
values, and Native/wasm1 results agree. Core evaluator APIs receive explicit
time values and never read the host clock directly.

## Microbenchmark snapshot

Command:

```bash
moon -C spikes/ecosystem bench --target native --release
moon -C spikes/ecosystem bench --target wasm --release
```

These are one-machine Phase 0 observations, not release thresholds. Each value
is the reported mean across ten calibrated batches.

| Operation | Native | wasm1 |
| --- | ---: | ---: |
| UTF-8 encode, small source fixture | 36.92 ns | 135.69 ns |
| cached regexp match | 1.59 us | 4.35 us |
| regexp compile and match | 10.29 us | 27.84 us |
| cmark parse with layout and locations | 1.59 us | 3.99 us |

No performance threshold is frozen from these tiny fixtures. PR-020, PR-036,
and PR-053 must add representative 1 KiB, 100 KiB, and adversarial corpora;
release gates compare medians on a controlled runner and investigate regression
rather than failing on workstation noise.

## Unproven and deferred

- Full byte-for-byte upstream tangle output and original-line reconstruction.
- Complete Rust `regex` syntax, Unicode, capture, and replacement compatibility.
- Local time-zone discovery, DST transitions, and chrono directive coverage.
- Browser, generic WASI, and wasm-gc host execution.
- Large-input allocation, denial-of-service budgets, and production dependency
  size after dead-code elimination.

These are assigned to explicit later PR gates. None is silently treated as
working because the Phase 0 contract passed.
