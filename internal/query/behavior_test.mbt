///|
async fn query_fixture(root : Bytes, child? : Bytes) -> @loader.LoadedGraph {
  let dir = @path.PathValue::new("/project", Unix)
  let host = @host_testkit.FakeHost::new(
    dir,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  let file = @path.PathValue::new("/project/justfile", Unix)
  host.put_file(file, root)
  if child is Some(bytes) {
    host.put_file(@path.PathValue::new("/project/child.just", Unix), bytes)
  }
  @loader.load_graph(host, file, @source.SourceId::new(708))
}

///|
async test "query summary filters private recipes and sorts names" {
  let graph = query_fixture(b"zeta:\n[private]\nhidden:\nalpha:\n")
  let project = @project.compile_loaded_graph(graph)
  let arguments = @cli.parse_arguments(["--summary"], Map([]))
  assert_true(@query.try_fast_summary(graph, arguments) is None)
  let request = @query.build_query(project, arguments)
  assert_false(request.needs_globals())
  let result = @query.render(request, graph, project, false, Map([]))
  assert_eq(result.stdout(), b"alpha zeta\n")
  assert_eq(result.stderr(), b"")
}

///|
async test "recursive list renders custom heading once and indents each module level" {
  let graph = query_fixture(b"mod child\nroot:\n", child=b"leaf:\n")
  let project = @project.compile_loaded_graph(graph)
  let arguments = @cli.parse_arguments(
    [
      "--list", "--list-submodules", "--list-heading", "Recipes\n", "--list-prefix",
      "> ",
    ],
    Map([]),
  )
  let request = @query.build_query(project, arguments)
  assert_true(request.needs_globals())
  let globals = Map([])
  for path in project.module_paths() {
    globals[path] = @evaluator.Environment::new()
  }
  let result = @query.render(request, graph, project, false, globals)
  assert_eq(result.stdout(), b"Recipes\n> root\n> child:\n> > leaf\n")
}

///|
async test "show follows the selected definition and alias across imports" {
  let root_source =
    #|set allow-duplicate-recipes
    #|import 'child.just'
    #|
    #|# wrong root comment
    #|pick first:
    #|
    #|# selected root comment
    #|pick root:
    #|
    #|alias fromroot := imported
  let imported_source =
    #|# shadowed comment
    #|pick losing:
    #|
    #|# first line
    #|# selected import comment
    #|[no-cd]
    #|imported arg:
    #|    @echo {{arg}}
    #|
    #|# alias doc
    #|[private]
    #|alias shortcut := pick
  let graph = query_fixture(
    @utf8.encode(root_source),
    child=@utf8.encode(imported_source),
  )
  let project = @project.compile_loaded_graph(graph)
  let root = "# selected root comment\npick root:\n"
  let imported = "# selected import comment\n[no-cd]\nimported arg:\n    @echo {{ arg }}\n"
  for
    (recipe, expected) in [
      ("pick", root),
      ("imported", imported),
      ("shortcut", "alias shortcut := pick\n" + root),
      ("fromroot", "alias fromroot := imported\n" + imported),
    ] {
    let request = @query.build_query(
      project,
      @cli.parse_arguments(["--show", recipe], Map([])),
    )
    let result = @query.render(request, graph, project, false, Map([]))
    assert_eq(result.stdout(), @utf8.encode(expected))
    assert_eq(result.stderr(), b"")
  }
}

///|
test "query model owns immutable rendered bytes" {
  let result = @query.QueryResult::new(stdout=b"ok\n", stderr=b"warning\n")
  assert_eq(result.stdout(), b"ok\n")
  assert_eq(result.stderr(), b"warning\n")
}
