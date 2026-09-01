///|
test "upstream recursion_limit::user_defined_function_recursion_limit" {
  let source = @source.Source::from_text(
    @source.SourceId::new(962),
    "justfile",
    "set unstable\n\nfoo() := foo()\n\nbar:\n    echo {{ foo() }}\n",
  )
  let compilation = try! @semantic.compile(try! @parser.parse(source))
  let expression = try! @parser.parse_expression(
    @source.Source::from_text(@source.SourceId::new(963), "expr", "foo()"),
  )
  try
    ignore(
      evaluate_with_context(
        expression,
        EvaluationContext::new(),
        functions=FunctionEnvironment::from_compilation(compilation),
      ),
    )
  catch {
    FunctionRecursionLimit(name~, limit~, ..) => {
      assert_eq(name, "foo")
      assert_true(limit >= 48)
    }
    error => fail("unexpected evaluator error: \{Repr(error)}")
  } noraise {
    _ => fail("expected user-defined function recursion limit")
  }
}
