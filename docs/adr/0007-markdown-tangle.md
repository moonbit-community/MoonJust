# ADR-0007: Markdown tangle adapter

- Status: Accepted
- Date: 2026-08-04

## Context

Markdown justfiles must extract top-level fenced `just` blocks while preserving
the original line layout for diagnostics. MoonJust source positions are UTF-8
byte offsets. The available cmark package has a rich CommonMark AST, but its
locations are MoonBit/UTF-16 code-unit positions and its public model is much
larger than MoonJust's required surface.

## Decision

- MoonJust owns a narrow `MarkdownExtractor` contract whose input and output
  use project `Source`, `Span`, and diagnostic types.
- Exact `moonbit-community/cmark 0.4.4` is the initial private implementation
  candidate for PR-036.
- The adapter considers only direct document fenced code blocks and applies the
  upstream first-info-token rule exactly.
- cmark positions are converted through the canonical UTF-8 byte line index;
  cmark AST, node, and location types never enter public or parser APIs.
- Production adoption requires byte-for-byte passage of all `just 1.57.0`
  tangle tests, CommonMark boundary tests, and explicit resource budgets.
- PR-104 repeats the dependency decision. If the gate fails, implement a
  specialized source-aware fenced-block extractor under the same contract.
- Markdown parsing never fetches links or executes embedded content.

## Consequences

The parser remains independent of a large third-party AST and can replace the
implementation without a public migration. Conversion costs are accepted for
Markdown input, which is a secondary load path. The Phase 0 result proved block
selection and position availability, not full tangle compatibility; that
historical spike was later removed after the project chose the in-project
parser implementation.
