# ADR-0003: Source and span model

- Status: Accepted
- Date: 2026-08-04

## Context

Upstream diagnostics and parser offsets are based on UTF-8 bytes. MoonBit
strings are UTF-16, so direct string indexing would produce incorrect offsets
for non-ASCII source and could split surrogate pairs.

## Decision

- Source text is stored as validated UTF-8 `Bytes`.
- A span is a half-open `SourceId + start_byte + end_byte` interval.
- Lexer syntax recognition operates on bytes for ASCII grammar tokens.
- Lexemes are decoded only at explicit boundaries.
- A line index converts byte offsets to line/column locations for rendering.
- Diagnostic display columns are computed separately from byte offsets and may
  use a verified Unicode width package.
- Markdown tangle output preserves source line count and a mapping to the
  original Markdown source.

## Consequences

Parser and AST APIs never expose MoonBit UTF-16 indexes as source positions.
Phase 1 must test ASCII, Chinese, combining marks, emoji, CRLF, invalid UTF-8,
empty input, and EOF spans before lexer implementation proceeds.
