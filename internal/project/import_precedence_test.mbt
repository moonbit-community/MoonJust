///|
async fn import_graph(files : Array[(String, Bytes)]) -> @loader.LoadedGraph {
  let host = project_host()
  for (name, contents) in files {
    host.put_file(@path.PathValue::new("/workspace/" + name, Unix), contents)
  }
  @loader.load_graph(
    host,
    @path.PathValue::new("/workspace/justfile", Unix),
    @source.SourceId::new(0),
  )
}

///|
async test "later shallow declarations displace deeper winners in input order" {
  let graph = import_graph([
    (
      "justfile", b"set allow-duplicate-recipes\nset allow-duplicate-variables\nimport 'left'\nimport 'right'\nroot:\n",
    ),
    ("left", b"import 'leaf'\nleft:\n"),
    ("leaf", b"v := 'deep'\npick deep:\nleaf:\n"),
    (
      "right", b"right:\nv := 'shallow'\npick shallow:\nalias shortcut := pick\n",
    ),
  ])
  let compilation = @project.compile_loaded_graph(graph).root()
  assert_eq(compilation.recipe_names(), [
    "root", "left", "leaf", "right", "pick",
  ])
  assert_eq(
    compilation.recipe("pick").unwrap().parameters()[0].name(),
    "shallow",
  )
  assert_true(
    compilation.variable("v").unwrap().value() is String(s) &&
    s.cooked() == "shallow",
  )
  assert_eq(compilation.alias_target("shortcut"), Some("pick"))
}

///|
async test "root and imported aliases reach semantic redefinition checks" {
  for
    root in [
      b"import 'child'\nalias run := first\nfirst:\n", b"set allow-duplicate-recipes\nset allow-duplicate-variables\nimport 'child'\nalias run := first\nfirst:\n",
    ] {
    let graph = import_graph([
      ("justfile", root),
      ("child", b"alias run := second\nsecond:\n"),
    ])
    try @project.compile_loaded_graph(graph) catch {
      Semantic(
        SymbolRedefinition(
          name="run",
          first_kind="alias",
          second_kind="alias",
          ..
        ),
      ) => ()
      error => fail("unexpected error \{Repr(error)}")
    } noraise {
      _ => fail("expected duplicate alias")
    }
  }
}

///|
async test "equal-depth duplicates retain the first and second diagnostic spans" {
  let graph = import_graph([
    ("justfile", b"import 'left'\nimport 'right'\n"),
    ("left", b"a:\nrepeat:\n"),
    ("right", b"repeat:\n"),
  ])
  try @project.compile_loaded_graph(graph) catch {
    Semantic(DuplicateRecipe(name~, first~, second~)) => {
      assert_eq(name, "repeat")
      assert_eq(first.source_id(), graph.files()[1].ast().source_id())
      assert_eq(second.source_id(), graph.files()[2].ast().source_id())
      assert_eq(first.start_byte(), 3)
      assert_eq(second.start_byte(), 0)
    }
    error => fail("unexpected error \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate recipe")
  }
}

///|
async test "the same imported file has independent winners in two modules" {
  let graph = import_graph([
    ("justfile", b"mod one 'one.just'\nmod two 'two.just'\n"),
    (
      "one.just", b"set allow-duplicate-recipes\nimport 'common.just'\npick one:\n",
    ),
    ("two.just", b"import 'common.just'\n"),
    ("common.just", b"import 'leaf.just'\n"),
    ("leaf.just", b"pick shared:\nshared:\n"),
  ])
  let project = @project.compile_loaded_graph(graph)
  for (name, parameter) in [("one", "one"), ("two", "shared")] {
    let module_ = project
      .module_compilation(@modulepath.ModulePath::parse(name))
      .unwrap()
    assert_eq(module_.recipe_names(), ["pick", "shared"])
    assert_eq(module_.recipe("pick").unwrap().parameters()[0].name(), parameter)
  }
}
