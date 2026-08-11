# Phase 3 completion report

- Status: Implemented; Phase 3 exit passed
- Strict review: 2026-08-06 ([Phase 0-9 audit](PHASE_0_9_AUDIT.md))
- Historical phase snapshot; the current cross-phase verdict is in the audit above.
- Upstream baseline: `just 1.57.0`
- Required implementation targets: Native and wasm1
- Scope: parser-owned AST, recursive-descent grammar, canonical formatter, and source-aware Markdown tangle

The strict remediation is complete. Every applicable upstream parser,
formatter, Markdown, and tangle registration is linked to a deterministic
case manifest and executable Native/wasm1 suite. The formatter also enforces a
span-free semantic AST fingerprint before and after canonical printing.

## Delivered contracts

| Unit | Implementation | Evidence |
| --- | --- | --- |
| PR-030 | `src/syntax` expression nodes and bounded precedence parser | Native/wasm expression, call, list, conditional, string-escape and span tests |
| PR-031/032 | assignment, alias, recipe parameters, dependencies and body fragments | representative justfile grammar corpus and interpolation tests |
| PR-033/034 | typed settings/attributes plus import/module/optional syntax | complete registered settings/attributes inventory and unknown-name errors |
| PR-035 | canonical formatter, check result and diff output | formatter idempotence and canonical indentation tests |
| PR-036 | source-aware fenced `just` Markdown extractor | nested/indented/commented fence cases and byte-offset preservation |
| PR-037 | parser depth/node and Markdown line/byte budgets | malformed corpus and resource-limit tests |

## Frozen parser decisions

- AST spans remain half-open UTF-8 byte spans owned by the original `SourceId`.
- Parser and formatter never import `host`, async runtimes, target FFI, or filesystem APIs.
- Lexer errors are wrapped as typed parser failures with stable `MJ-PARSE-0000` provenance.
- Markdown tangle replaces excluded line bytes with spaces and preserves line terminators, so diagnostics keep original byte offsets.
- Formatter output is deterministic, uses four-space recipe indentation, and is idempotent.

## Exit evidence

- All parser and formatter package tests pass on Native and wasm1 (13 parser,
  10 formatter/Markdown tests per target).
- The pinned upstream map contains 181 parser, 127 formatter, 11 Markdown, and
  5 tangle registrations, all `covered-by` with executable suite and tracking
  evidence in `tests/upstream/just-1.57.0/phase-3-cases.jsonl`. Every row also
  carries a `suite`/`test_name` anchor verified against the MoonBit test
  declaration; repeated anchors explicitly denote family-level coverage.
- `Expression::semantic_key`, `Item::semantic_key`, and `Ast::semantic_key`
  provide the machine-checked span-free semantic equivalence gate used by the
  formatter test.
- Markdown fences accept zero through three leading spaces, reject four-space
  indented fences, require matching character/minimum length, and preserve
  original line and byte offsets.
- `moon check --target all --warn-list +73` passes without warnings.
- `moon info` generated interfaces were reviewed for the new syntax/parser/formatter public surface.
- `tools/check_architecture.sh` includes all nine Phase 1-3 package boundaries.

Phase 4 may consume the public `Ast`, `Item`, `Expression`, `Recipe`, and `Parser` APIs without accessing parser internals.
