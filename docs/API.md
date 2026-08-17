# Public API

The executable guide and documentation tests are in
[`api/API.mbt.md`](../api/API.mbt.md). The only stable library package is
`moonbit-community/MoonJust/api`; all implementation packages live below
`internal/` and are outside the module's public boundary.

The stable operations are:

- `version`, `version_line`, and `just_compatibility_target` for product and
  pinned-oracle identity;
- `check_source` for single-file syntax and same-file semantic validation;
- `format_text` for pure in-memory formatting;
- `recipe_names` for sorted, public root recipe names matching the default
  `just --summary` visibility rules.

Invalid input raises `ApiError::InvalidSource(Array[ApiDiagnostic])`.
Diagnostics expose owned error codes, messages, source names, and optional
one-based source ranges. No parser, AST, semantic, evaluator, host, compilation,
environment, or executor type is part of the stable interface.

`api/pkg.generated.mbti` is the release-review baseline. Run `moon info` and
review its complete diff whenever this facade changes.
