# ADR-0014: Phase 7 invocation parser

- Status: Accepted
- Date: 2026-08-08

## Context

The global CLI parser and recipe invocation parser solve different grammars.
The former owns MoonJust options and command modes. After the first recipe
argument, upstream `just` uses trailing-var-arg behavior and passes every token
to the recipe parser, including tokens which spell global options.

Recipe parsing must then group multiple invocations, positional and variadic
parameters, `[arg]` long and short options, flags, repeated values, count
constraints, and anchored patterns. `value=` and `pattern=` properties are
expressions rather than static strings.

## Decision

- `internal/invocation` is a pure core package. It consumes an immutable semantic
  compilation and recipe argv and returns immutable invocations with one value
  group per parameter.
- The CLI parser inserts its own argument boundary before the first recipe.
  Known global options are parsed only before that boundary. The original
  recipe `--` separator is preserved for invocation parsing.
- Argument attributes are compiled before argv is consumed. Option names,
  duplicates, required list mode, incompatible properties, min/max values, and
  regular expressions are rejected deterministically.
- Global assignments are evaluated through the existing evaluator. `pattern=`
  is evaluated in global scope; `value=` is evaluated in declaration order
  with preceding recipe parameters in scope. List results and repeated values
  preserve individual elements before count and pattern checks.
- Invocation failures have stable `MJ-INV-*` codes and upstream-compatible
  messages. Evaluation failures remain typed and are wrapped without losing
  their original diagnostic information.
- The application composition root validates invocations before reaching the
  explicit Phase 8 executor boundary. No process capability is granted and no
  recipe command is run in Phase 7.

## Consequences

Phase 8 can consume parsed invocations without reparsing global argv or
reaching into syntax attributes. Native and Wasm usage output is compared byte
for byte with pinned `just 1.57.0`; recipe argv success and failure cases use a
separate differential probe so validation does not depend on an unfinished
executor.

The package imports the evaluator but no Host capability. Effectful `value=`
expressions fail explicitly until execution composition supplies an approved
effect context in a later phase.
