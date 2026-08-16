# MoonJust public API

The stable facade is the `moonbit-community/MoonJust/api` package. Construct
source text with an explicit source identity, then parse, format, or compile it.

```mbt check
///|
test "parse source through the stable facade" {
  let source = @source.Source::from_text(
    @source.SourceId::new(1),
    "example.just",
    "hello:\n  echo hello\n",
  )
  let ast = @api.parse(source)
  assert_eq(ast.items().length(), 1)
}
```

Formatting is pure and does not mutate the input file:

```mbt check
///|
test "format source through the stable facade" {
  let source = @source.Source::from_text(
    @source.SourceId::new(2),
    "example.just",
    "hello:\n  echo hello\n",
  )
  let formatted = @api.format_source(source)
  assert_true(formatted.contains("hello:"))
}
```

Compilation parses and statically validates one source:

```mbt check
///|
test "compile source through the stable facade" {
  let source = @source.Source::from_text(
    @source.SourceId::new(3),
    "example.just",
    "hello:\n  echo hello\n",
  )
  let compilation = @api.compile_source(source)
  assert_eq(compilation.recipe_names().length(), 1)
  assert_eq(compilation.recipe_names()[0], "hello")
}
```

`evaluate_expression` evaluates a parsed expression with an explicit
environment and resource budget. It does not grant host filesystem,
environment, clock, random, or process capabilities.

The formal public surface is committed in `api/pkg.generated.mbti`. Run
`moon info` after API changes and review the resulting interface diff.
