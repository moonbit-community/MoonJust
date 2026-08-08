# Phase 2 completion report

- Status: Complete
- Review date: 2026-08-04
- Upstream baseline: `just 1.57.0`
- Required implementation targets: Native and wasm1
- Decision: Proceed to Phase 3 (`Parser`, AST, and formatter)
- Historical phase snapshot; the current cross-phase verdict is in
  [`PHASE_0_7_AUDIT.md`](PHASE_0_7_AUDIT.md).

## Scope statement

Phase 2 implements the target-independent justfile lexer on top of Phase 1's
validated UTF-8 `Source` and byte `Span` model. It covers normal tokens,
strings, indentation, recipe text, recipe interpolation, and format strings.
It does not parse expressions, validate parser-owned string escape syntax,
construct an AST, format a justfile, or execute recipes.

The 2026-08-06 re-certification links all 93 pinned lexer registrations to the
machine-readable upstream map, verifies the 20 lexer package tests on Native
and wasm1, and retains the 100,000-input hardening budget. The Rust-private
`presume_error` helper remains explicitly not applicable.

Coverage note: the lexer hardening count is machine-verified; uncovered parser
and evaluator branches belong to their remediation PRs and are not waived by
this Phase 2 re-certification.

## Work units

| Plan unit | Commit | Delivered evidence |
| --- | --- | --- |
| PR-020 | `0903edb` | Upstream-aligned TokenKind and Keyword inventories, byte-span Token/TokenStream API, normal scanner, delimiter and line-continuation errors |
| PR-021 | `a07ec58` | Raw/cooked/backtick strings, all single/triple delimiters, multiline/Unicode behavior, unterminated diagnostics |
| PR-022 | `80f0653` | Indentation stack, blank-line lookahead, zero-width Dedent, tabs/spaces and inconsistent indentation errors, CRLF/EOF behavior |
| PR-023 | `238c680` | Recipe text, prefix preservation, brace escape, recipe interpolation, nested delimiters, format-string start/continue/end modes |
| PR-024 | Phase 2 final commit | Resource budgets, stable diagnostic conversion, 100,000-input property test, upstream oracle corpus, architecture and compatibility gates |

## Exit evidence

| Exit | Evidence | Result |
| --- | --- | --- |
| Normal token compatibility | Exact inventories for 42 TokenKind variants and 42 parser keywords; operators, identifiers, comments, BOM, newline, continuation and delimiter tests | Pass |
| String boundaries | Six delimiter forms, raw/cooked behavior, escaped delimiters, multiline and multibyte input, precise unterminated spans | Pass |
| Indentation behavior | Nested increase/decrease, tabs/spaces, blank lines, CRLF, delimiter continuation and EOF synthetic tokens | Pass |
| Context-sensitive modes | Recipe text and prefixes, `{{{{`, empty/expression interpolation, nested mismatch, adjacent `f` and triple format strings | Pass |
| Upstream inventory | 93 `lexer::tests` registrations are machine-counted; 92 are behavioral and one is Rust-private `presume_error` | Pass |
| Upstream oracle | 16 successful and 5 error cases adapted from `just 1.57.0/src/lexer.rs`, with CC0 provenance and byte-for-byte round-trip checks | Pass |
| Property hardening | 100,000 deterministic valid UTF-8 inputs; every success validates round-trip, monotonic/in-bounds spans, source identity, EOF and synthetic-token invariants | Pass |
| Resource safety | Configurable source-byte, token-count and combined nesting budgets; invalid configurations and exhausted budgets are typed | Pass |
| Cross-target package tests | The scoped lexer package passed 20/20 tests on Native and wasm1, including hardening; the cumulative Phase 2 exit suite passed 109/108 | Pass |
| Stable backend checks | `moon check --target all --warn-list +73` completes without warnings | Pass |
| Architecture boundary | `src/lexer` is included in the pure-core architecture closure and imports no Host package, target FFI, async runtime or third-party production dependency | Pass |
| Public API review | Generated `pkg.generated.mbti` commits opaque Token/TokenStream/LexerLimits records and explicit read-only accessors | Pass |

The machine-readable result is `compat/phase-2.toml`. The upstream snapshot
verifier checks its five implemented contracts, Native/wasm1 evidence, the 93
registered lexer tests, the 100,000-input budget, and oracle case counts.

## Frozen decisions

- Lexer input is validated UTF-8, but all token and error locations remain
  half-open byte spans.
- Keywords remain `Identifier` tokens and are resolved explicitly by
  `Keyword::from_lexeme` in grammar context, matching upstream layering.
- Cooked-string lexing protects escaped delimiters. Semantic validation of
  escapes, including `\u{...}`, remains parser-owned as it is upstream.
- Indent consumes source whitespace; Dedent and EOF are synthetic zero-width
  tokens. Token spans are monotonic and source-bound.
- Recipe bodies and interpolations are explicit modes. Recipe interpolation
  and delimiter/format-string nesting use separate stacks.
- The default untrusted-input budgets are 16 MiB source text, 1,000,000 tokens,
  and 1,024 combined indentation/delimiter/interpolation levels.
- Lexer failures expose stable `MJ-LEX-0001` through `MJ-LEX-0016` diagnostic
  codes and convert to the shared diagnostic IR without terminal concerns.

## Known limitations and assigned gates

- The 92 behavioral upstream registrations are inventoried, while 21 key cases
  are adapted as literal MoonBit oracle fixtures. The remaining registrations
  are covered by feature-family and property tests rather than copied one for
  one. Parser integration in PR-030 through PR-037 will add end-to-end grammar
  differentials.
- Invalid cooked-string escape syntax is intentionally accepted as one token;
  PR-030 owns the upstream parser error kind and exact character position.
- An unclosed ordinary delimiter or format interpolation that reaches EOF is
  represented in the token stream and rejected by the parser, matching the
  upstream lexer/parser responsibility split.
- MoonJust's finite default budgets can reject exceptionally large inputs that
  upstream accepts. Embedders may raise them explicitly; release documentation
  must retain this security boundary.
- No Phase 2 package loads files or executes justfiles. At the Phase 2 snapshot,
  the command remained a version-only skeleton.

No limitation above blocks Phase 3. Each is either deliberate upstream
layering or assigned to the first phase that has enough grammar context to
resolve it without duplicating logic in the lexer.

## Phase 3 entry

PR-030 must consume only the public TokenStream/Token/Keyword APIs, preserve
byte spans in AST nodes, validate parser-owned escapes, and apply its own
recursion/resource budgets. Parser tests must run on Native and wasm1 and must
not introduce Host dependencies into the pure core.
