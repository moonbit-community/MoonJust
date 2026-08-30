///|
test "planner preserves dependency order and dry-run output" {
  let source = @source.Source::from_text(
    @source.SourceId::new(709),
    "justfile",
    "prepare:\n  echo prepare\nbuild: prepare\n  echo build\n",
  )
  let compilation = try! @semantic.compile(try! @parser.parse(source))
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let plan = try! plan_recipe_graph(
    compilation,
    [RecipeRequest::new("build")],
    @evaluator.Environment::new(),
    shell,
    @path.PathValue::new("/workspace", Unix),
    options=ExecutionOptions::new(),
  )
  assert_eq(plan.commands().length(), 2)
  assert_eq(plan.commands()[0].recipe(), "prepare")
  assert_eq(plan.commands()[1].recipe(), "build")
  let dry = try! plan_recipe_graph(
    compilation,
    [RecipeRequest::new("build")],
    @evaluator.Environment::new(),
    shell,
    @path.PathValue::new("/workspace", Unix),
    options=ExecutionOptions::new(dry_run=true),
  )
  assert_true(dry.options().dry_run())
  assert_true(dry.commands().is_empty())
  assert_true(dry.stderr().length() > 0)
}
