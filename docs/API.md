# Public API

The executable API guide and compiled examples are in
[`api/API.mbt.md`](../api/API.mbt.md). This file is retained as a stable
documentation index for source packages and generated Mooncakes documentation.

MoonJust's supported library surface is the
`moonbit-community/MoonJust/api` package. Its generated interface is committed
as `api/pkg.generated.mbti`; target-specific adapters and executable
composition are not part of the stable public API unless explicitly documented
here.

`parse` preserves UTF-8 byte spans, `format_source` returns canonical source,
and `compile_source` performs static validation without filesystem or process
access. Loading imports and modules remains an explicit host-level operation.

## Evaluate

`evaluate_expression` evaluates a parsed expression with an explicit
environment and evaluation budget. It is the pure evaluator facade; host
effects such as filesystem access, environment lookup and process spawning are
not granted by this function.

## Build identity

`version`, `compatible_just_version`, and `version_line` expose the MoonJust
application version and the pinned upstream oracle baseline. The version line
records compatibility with the completed `just 1.57.0` Tier A gate.

Run `moon info` to regenerate the formal interfaces and `moon doc` to generate
the complete package documentation from committed `///` comments.
