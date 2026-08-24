# MoonJust public API

`ZSeanYves/MoonJust/api` is the only stable library package. Its
in-memory operations do not read imports or access host capabilities.

```mbt check
///|
test "check and format one source" {
  let text = "hello:\n  echo hello\n"
  @api.check_source(text, source_name="example.just")
  assert_eq(
    @api.format_text(text, source_name="example.just"),
    "hello:\n    echo hello\n",
  )
}
```

`recipe_names` follows the default root-level `just --summary` visibility and
ordering rules: private recipes and names beginning with `_` are omitted.

```mbt check
///|
test "list public recipes" {
  let text =
    #|zeta:
    #|  true
    #|_hidden:
    #|  true
    #|alpha:
    #|  true
    #|
  assert_eq(@api.recipe_names(text), ["alpha", "zeta"])
}
```

Invalid input raises `ApiError::InvalidSource`. Each `ApiDiagnostic` owns its
code, message, source name, and optional one-based source range; no parser,
AST, semantic, evaluator, host, or executor type crosses the stable boundary.

The formal release surface is committed in `api/pkg.generated.mbti`. Run
`moon info` after API changes and review that file before release.
