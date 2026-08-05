# Phase 3 completion report

- Status: Complete
- Review date: 2026-08-05
- Upstream baseline: `just 1.57.0`
- Required implementation targets: Native and wasm1
- Scope: parser-owned AST, recursive-descent grammar, canonical formatter, and source-aware Markdown tangle

Phase 3 is accepted against the original plan exits. Its provenance-backed
grammar, formatter, Markdown, recovery, and fuzz evidence is frozen in
`compat/phase-3.toml` and enforced by `tools/upstream/verify_snapshot.sh`.

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

- All parser and formatter package tests pass on Native and wasm1.
- `moon check --target all --warn-list +73` passes without warnings.
- `moon info` generated interfaces were reviewed for the new syntax/parser/formatter public surface.
- `tools/check_architecture.sh` includes all nine Phase 1-3 package boundaries.

Phase 4 may consume the public `Ast`, `Item`, `Expression`, `Recipe`, and `Parser` APIs without accessing parser internals.
