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
async test "cross-file recipe redefinition highlights the later line" {
  let graph = import_graph([
    ("justfile", b"import 'left'\nimport 'right'\n"),
    ("left", b"a:\nrepeat:\n"),
    ("right", b"repeat:\n"),
  ])
  try @project.compile_loaded_graph(graph) catch {
    Semantic(DuplicateRecipe(name~, first~, second~)) => {
      assert_eq(name, "repeat")
      assert_eq(first.source_id(), graph.files()[2].ast().source_id())
      assert_eq(second.source_id(), graph.files()[1].ast().source_id())
      assert_eq(first.start_byte(), 0)
      assert_eq(second.start_byte(), 3)
    }
    error => fail("unexpected error \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate recipe")
  }
}

///|
async test "tied alias lines highlight the first listed sibling's identifier" {
  for
    (root, column) in [
      (b"import 'left'\nimport 'right'\ntarget:\n", 8),
      (b"import 'right'\nimport 'left'\ntarget:\n", 6),
    ] {
    let graph = import_graph([
      ("justfile", root),
      ("left", b"alias   run := target\n"),
      ("right", b"alias\trun := target\n"),
    ])
    try @project.compile_loaded_graph(graph) catch {
      Semantic(SymbolRedefinition(name="run", first~, second~, ..)) => {
        assert_eq(first.source_id(), graph.files()[2].source().id())
        assert_eq(second.source_id(), graph.files()[1].source().id())
        assert_eq(second.start_byte(), column)
        assert_eq(second.length(), 3)
      }
      error => fail("unexpected error \{Repr(error)}")
    } noraise {
      _ => fail("expected duplicate alias")
    }
  }
}

///|
async test "enabled duplicate settings select the first listed sibling" {
  for
    (root, expected) in [
      (b"import 'left'\nimport 'right'\n", "left"),
      (b"import 'right'\nimport 'left'\n", "right"),
    ] {
    let graph = import_graph([
      ("justfile", root),
      ("left", b"set allow-duplicate-recipes\nr left:\nv := 'left'\n"),
      (
        "right", b"set allow-duplicate-variables := true\nr right:\nv := 'right'\n",
      ),
    ])
    let c = @project.compile_loaded_graph(graph).root()
    assert_eq(c.recipe("r").unwrap().parameters()[0].name(), expected)
    assert_true(
      c.variable("v").unwrap().value() is String(v) && v.cooked() == expected,
    )
  }
}

///|
async test "cross-depth duplicate settings are independent" {
  let variable = import_graph([
    (
      "justfile", b"import 'child'\nset allow-duplicate-recipes\nr:\nv := 'root'\n",
    ),
    (
      "child", b"set allow-duplicate-variables := false\nr:\nexport   v := 'child'\n",
    ),
  ])
  try @project.compile_loaded_graph(variable) catch {
    Semantic(DuplicateVariable(name="v", second~, ..)) => {
      let source = variable.files()[1].source()
      assert_eq(source.slice_text(second), "v")
      assert_eq(source.locate(second.start_byte()).byte_column(), 9)
    }
    error => fail("unexpected error \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate variable")
  }
  let recipe = import_graph([
    (
      "justfile", b"import 'child'\nset allow-duplicate-variables\nr:\nv := 'root'\n",
    ),
    ("child", b"r:\nv := 'child'\n"),
  ])
  try @project.compile_loaded_graph(recipe) catch {
    Semantic(DuplicateRecipe(name="r", ..)) => ()
    error => fail("unexpected error \{Repr(error)}")
  } noraise {
    _ => fail("expected duplicate recipe")
  }
}

///|
async test "a file imported both directly and transitively uses the compiler's first path" {
  let graph = import_graph([
    (
      "justfile", b"set allow-duplicate-variables\nimport 'branch'\nimport 'shared'\nimport 'peer'\n",
    ),
    ("branch", b"import 'shared'\nbranch:\n"),
    ("shared", b"v := 'shared'\nshared:\n"),
    ("peer", b"v := 'peer'\npeer:\n"),
  ])
  let c = @project.compile_loaded_graph(graph).root()
  assert_true(
    c.variable("v").unwrap().value() is String(v) && v.cooked() == "shared",
  )
  assert_eq(c.recipe_names(), ["branch", "shared", "peer"])
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
