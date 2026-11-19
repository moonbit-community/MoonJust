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
test "upstream invocation_parser::tests::recipe_in_submodule" {
  let project = try! upstream_project("", "bar:\n")
  let invocations = try! @invocation.parse_project_invocations(project, [
    "foo", "bar",
  ])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].module_path().as_string(), "foo")
  assert_eq(invocations[0].invocation().recipe(), "bar")
  assert_true(invocations[0].invocation().arguments().is_empty())
}

///|
test "upstream invocation_parser::tests::recipe_in_submodule_path_unknown" {
  let project = try! upstream_project("", "bar:\n")
  try @invocation.parse_project_invocations(project, ["foo::zzz"]) catch {
    UnknownRecipe(recipe="foo::zzz") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown module recipe")
  }
}

///|
test "upstream invocation_parser::tests::recipe_in_submodule_unknown" {
  let project = try! upstream_project("", "bar:\n")
  try @invocation.parse_project_invocations(project, ["foo", "zzz"]) catch {
    UnknownRecipe(recipe="foo zzz") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unknown submodule recipe")
  }
}

///|
test "upstream invocation_parser::tests::module_path_not_consumed" {
  let project = try! upstream_project("", "bar:\n")
  try @invocation.parse_project_invocations(project, ["foo::bar::baz"]) catch {
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
  try @invocation.parse_project_invocations(project, ["foo::bar"]) catch {
    OptionalModuleAbsent(module_path="foo") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected absent module error")
  }
}

///|
async test "upstream invocation_parser::tests::module_alias" {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  let justfile = cwd.join(@path.PathValue::new("justfile", Unix))
  host.put_file(justfile, b"mod foo\nalias f := foo\n")
  host.put_file(cwd.join(@path.PathValue::new("foo.just", Unix)), b"bar:\n")
  let request = @project.ProjectLoadRequest::new(
    @project.ProjectInput::new(cwd),
    File(justfile),
    [],
    @semantic.TargetPlatform::new(Linux, true),
    [],
  )
  let snapshot = @project.load_snapshot(host, request)
  let invocations = @invocation.resolve_project_invocations(
    snapshot.compilation(),
    ["f", "bar"],
  )
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].module_path().as_string(), "foo")
  assert_eq(invocations[0].invocation().recipe(), "bar")
  assert_true(invocations[0].invocation().arguments().is_empty())
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
  try @invocation.parse_project_invocations(project, []) catch {
    NoDefaultRecipe => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected no default recipe")
  }
}

///|
test "upstream invocation_parser::tests::trailing_separator_not_last_argument" {
  let project = try! upstream_project("", "bar:\n")
  try @invocation.parse_project_invocations(project, ["foo::", "bar"]) catch {
    UnknownRecipe(recipe="foo::") => ()
    error => fail("unexpected invocation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid trailing separator")
  }
}

///|
test "upstream invocation_parser::tests::trailing_separator_runs_default_recipe" {
  let project = try! upstream_project("", "bar:\n")
  let invocations = try! @invocation.parse_project_invocations(project, [
    "foo::",
  ])
  assert_eq(invocations.length(), 1)
  assert_eq(invocations[0].module_path().as_string(), "foo")
  assert_eq(invocations[0].invocation().recipe(), "bar")
  assert_true(invocations[0].invocation().arguments().is_empty())
}
