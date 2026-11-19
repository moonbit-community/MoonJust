///|
async test "query render errors retain the graph and prefixed search directory" {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let subdir = @path.PathValue::new("/workspace/sub", Unix)
  let file = @path.PathValue::new("/workspace/sub/justfile", Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  host.put_directory(subdir)
  host.put_file(file, b"hello:\n")
  let arguments = @cli.parse_arguments(["--show", "sub/missing"], Map([]))
  try
    execute_query_command(
      host,
      host,
      arguments,
      @project.ProjectInput::new(cwd),
    )
  catch {
    AtProject(Query(message), Some(graph), directory) => {
      assert_eq(message, "justfile does not contain recipe `missing`")
      assert_eq(directory, subdir)
      assert_eq(graph.files()[0].path(), file)
      assert_eq(graph.files()[0].source().text(), "hello:\n")
    }
    error => fail("unexpected query error: \{Repr(error)}")
  } noraise {
    _ => fail("expected --show to reject the missing recipe")
  }
}

///|
async test "default-list validates overrides before evaluating globals" {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  host.put_file(
    file, b"set default-list\nv := error('unexpected evaluation')\nhello:\n",
  )
  let arguments = @cli.parse_arguments(["missing=value"], Map([]))
  let snapshot = load_project_snapshot(
    host,
    arguments,
    @project.ProjectInput::new(cwd),
    @semantic.TargetPlatform::new(Linux, true),
    [],
  )
  try default_list_response(host, arguments, snapshot) catch {
    Query(message) =>
      assert_eq(
        message, "variable `missing` overridden on the command line but not present in justfile",
      )
    error => fail("unexpected default-list error: \{Repr(error)}")
  } noraise {
    _ => fail("expected the unknown override to be rejected")
  }
}

///|
async test "inspect compilation errors retain the source graph" {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  host.put_file(file, b"one := missing_variable\n")
  let arguments = @cli.parse_arguments(["--dump"], Map([]))
  try
    execute_inspect_command(host, arguments, @project.ProjectInput::new(cwd))
  catch {
    AtProject(Semantic(_), Some(graph), directory) => {
      assert_eq(directory, cwd)
      assert_eq(graph.files()[0].source().text(), "one := missing_variable\n")
    }
    error => fail("unexpected inspect error: \{Repr(error)}")
  } noraise {
    _ => fail("expected --dump to reject the undefined variable")
  }
}
