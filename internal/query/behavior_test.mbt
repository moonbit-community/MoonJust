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
  let result = @query.render(request, graph, project, false)
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
  let result = @query.render(request, graph, project, false)
  assert_eq(result.stdout(), b"Recipes\n> root\n> child:\n> > leaf\n")
}

///|
async test "list and default-list resolve only metadata in its declaring module" {
  let root =
    #|set default-list
    #|unused := style('bold')
    #|base := 'root'
    #|text := base + ' doc'
    #|[doc(text)]
    #|hello:
    #|[doc(text)]
    #|mod child
  let child =
    #|base := 'child'
    #|unused := error('unexpected')
    #|[doc(base)]
    #|leaf:
  let graph = query_fixture(@utf8.encode(root), child=@utf8.encode(child))
  let project = @project.compile_loaded_graph(graph)
  let path = @modulepath.ModulePath::root()
  let arguments = @cli.parse_arguments(["--list"], Map([]))
  let overrides = Map([(path, [("base", "override")])])
  for
    request in [
      @query.build_query(project, arguments),
      @query.QueryRequest::default_list(path, @cli.parse_arguments([], Map([]))),
    ] {
    let result = @query.render(request, graph, project, false, overrides~)
    assert_eq(
      result.stdout(),
      b"Available recipes:\n    hello     # override doc\n    child ... # override doc\n",
    )
    assert_eq(result.stderr(), b"")
  }
  let child_list = @query.build_query(
    project,
    @cli.parse_arguments(["--list", "child"], Map([])),
  )
  assert_eq(
    @query.render(child_list, graph, project, false, overrides~).stdout(),
    b"Available recipes:\n    leaf # child\n",
  )
}

///|
async test "module usage uses the requested alias, local options, docs and source order" {
  let graph = query_fixture(
    b"mod child\nalias c := child\nalias leaf := child::a\nunused := style('bold')\n",
    child=b"doc := 'detail'\n# last\nz:\n[doc(\" line 1\\nline 2 \")]\n[arg('opt', short='o', help=doc)]\na first opt:\n_hidden:\n",
  )
  let project = @project.compile_loaded_graph(graph)
  let names = ["--unsorted", "--usage", "c"]
  let req = @query.build_query(project, @cli.parse_arguments(names, Map([])))
  let output = @query.render(req, graph, project, false)
  assert_eq(
    output.stdout(),
    b"Usage:\n    # last\n    just c z\n\n    # line 1\n    # line 2\n    just c a [OPTIONS] first\n      first\n      -o opt detail\n",
  )
  let recipe = @query.build_query(
    project,
    @cli.parse_arguments(["--usage", "c::a"], Map([])),
  )
  assert_eq(
    @query.render(recipe, graph, project, false).stdout(),
    b"Usage: just c::a [OPTIONS] first\n\nArguments:\n  first\n\nOptions:\n  -o opt detail\n",
  )
  let spaced = @query.build_query(
    project,
    @cli.parse_arguments(["--usage", "  c  a  "], Map([])),
  )
  assert_eq(
    @query.render(spaced, graph, project, false).stdout(),
    b"Usage: just c a [OPTIONS] first\n\nArguments:\n  first\n\nOptions:\n  -o opt detail\n",
  )
  let shown = @query.build_query(
    project,
    @cli.parse_arguments(["--show", "c", "a"], Map([])),
  )
  assert_eq(
    @query.render(shown, graph, project, false).stdout(),
    b"[arg('opt', short='o', help=doc)]\n[doc(\" line 1\\nline 2 \")]\na first opt:\n",
  )
  let list = @query.build_query(
    project,
    @cli.parse_arguments(["--list"], Map([])),
  )
  assert_eq(
    @query.render(list, graph, project, false).stdout(),
    b"Available recipes:\n    leaf [OPTIONS] first # alias for `child::a`\n    child ...\n",
  )
}

///|
async test "list and default-list report errors in metadata of unlisted recipes" {
  let graph = query_fixture(
    b"x := assert('x' == 'y', 'failed')\n[private]\n[doc(x)]\nhidden:\nhello:\n",
  )
  let project = @project.compile_loaded_graph(graph)
  let arguments = @cli.parse_arguments(["--list"], Map([]))
  for
    request in [
      @query.build_query(project, arguments),
      @query.QueryRequest::default_list(
        @modulepath.ModulePath::root(),
        arguments,
      ),
    ] {
    let message = try {
      ignore(@query.render(request, graph, project, false))
      None
    } catch {
      @query.Evaluation(error) => Some(error.message())
      other => raise other
    }
    assert_eq(message, Some("assert failed: failed"))
  }
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
    let result = @query.render(request, graph, project, false)
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
