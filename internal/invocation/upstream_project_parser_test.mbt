///|
fn upstream_project(
  root_text : String,
  module_text : String,
) -> @semantic.ProjectCompilation raise {
  let root = @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(920), "justfile", root_text),
    allow_unstable=true,
  )
  let child_compilation = @semantic.compile_source(
    @source.Source::from_text(
      @source.SourceId::new(921),
      "foo.just",
      module_text,
    ),
    allow_unstable=true,
  )
  let root_path = @modulepath.ModulePath::root()
  let module_path = try! @modulepath.ModulePath::parse("foo")
  @semantic.ProjectCompilation::new([
    @semantic.ProjectModule::new(
      root_path,
      root,
      @path.PathValue::new("/workspace", Unix),
    ),
    @semantic.ProjectModule::new(
      module_path,
      child_compilation,
      @path.PathValue::new("/workspace/foo", Unix),
      default_recipe="bar",
    ),
  ])
}

///|
fn upstream_alias_project() -> @semantic.ProjectCompilation raise {
  let root_source = @source.Source::from_text(
    @source.SourceId::new(924),
    "justfile",
    "alias f := foo\n",
  )
  let root_ast = try! @parser.parse(root_source)
  let root = try! @semantic.compile(
    root_ast,
    allow_unstable=true,
    defer_recipe_linking=true,
  )
  let child = @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(925), "foo.just", "bar:\n"),
    allow_unstable=true,
  )
  let foo = try! @modulepath.ModulePath::parse("foo")
  @semantic.ProjectCompilation::new([
    @semantic.ProjectModule::new(
      @modulepath.ModulePath::root(),
      root,
      @path.PathValue::new("/workspace", Unix),
    ),
    @semantic.ProjectModule::new(
      foo,
      child,
      @path.PathValue::new("/workspace/foo", Unix),
      default_recipe="bar",
    ),
  ])
}

///|
test "upstream invocation_parser::tests::recipe_in_submodule" {
  let project = try! upstream_project("", "bar:\n")
  let invocations = try! parse_project_invocations(project, ["foo", "bar"])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].module_path().as_string(), "foo")
  assert_eq(invocations[0].invocation().recipe(), "bar")
  assert_true(invocations[0].invocation().arguments().is_empty())
}

///|
test "upstream invocation_parser::tests::recipe_in_submodule_path_unknown" {
  let project = try! upstream_project("", "bar:\n")
  try parse_project_invocations(project, ["foo::zzz"]) catch {
    UnknownRecipe(recipe="foo::zzz") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown module recipe")
  }
}

///|
test "upstream invocation_parser::tests::recipe_in_submodule_unknown" {
  let project = try! upstream_project("", "bar:\n")
  try parse_project_invocations(project, ["foo", "zzz"]) catch {
    UnknownRecipe(recipe="foo zzz") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown submodule recipe")
  }
}

///|
test "upstream invocation_parser::tests::module_path_not_consumed" {
  let project = try! upstream_project("", "bar:\n")
  try parse_project_invocations(project, ["foo::bar::baz"]) catch {
    ExpectedSubmoduleFoundRecipe(path="foo::bar") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected submodule error")
  }
}

///|
test "upstream invocation_parser::tests::recipe_in_absent_optional_module" {
  let root = try! @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(922), "justfile", ""),
    allow_unstable=true,
  )
  let absent = try! @modulepath.ModulePath::parse("foo")
  let project = try! @semantic.ProjectCompilation::new(
    [
      @semantic.ProjectModule::new(
        @modulepath.ModulePath::root(),
        root,
        @path.PathValue::new("/workspace", Unix),
      ),
    ],
    absent_modules=[absent],
  )
  try parse_project_invocations(project, ["foo::bar"]) catch {
    OptionalModuleAbsent(module_path="foo") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected absent module error")
  }
}

///|
test "upstream invocation_parser::tests::module_alias" {
  let project = try! upstream_alias_project()
  let invocations = try! parse_project_invocations(project, ["f", "bar"])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].module_path().as_string(), "foo")
  assert_eq(invocations[0].invocation().recipe(), "bar")
}

///|
test "upstream invocation_parser::tests::no_default_recipe" {
  let root = try! @semantic.compile_source(
    @source.Source::from_text(@source.SourceId::new(926), "justfile", "root:\n"),
    allow_unstable=true,
  )
  let project = try! @semantic.ProjectCompilation::new([
    @semantic.ProjectModule::new(
      @modulepath.ModulePath::root(),
      root,
      @path.PathValue::new("/workspace", Unix),
      source_file=@path.PathValue::new("/workspace/justfile", Unix),
    ),
  ])
  try parse_project_invocations(project, []) catch {
    NoDefaultRecipe => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected no default recipe")
  }
}

///|
test "upstream invocation_parser::tests::trailing_separator_not_last_argument" {
  let project = try! upstream_project("", "bar:\n")
  try parse_project_invocations(project, ["foo::", "bar"]) catch {
    UnknownRecipe(recipe="foo::") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid trailing separator")
  }
}

///|
test "upstream invocation_parser::tests::trailing_separator_runs_default_recipe" {
  let project = try! upstream_project("", "bar:\n")
  let invocations = try! parse_project_invocations(project, ["foo::"])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].module_path().as_string(), "foo")
  assert_eq(invocations[0].invocation().recipe(), "bar")
  assert_true(invocations[0].invocation().arguments().is_empty())
}
