///|
fn fake() -> @host.FakeHost raise @path.PathError {
  let cwd = @path.PathValue::new("/workspace/project", Unix)
  @host.FakeHost::new(cwd, @host.PlatformInfo::new(Linux, "x86_64", Unix))
}

///|
test "search ascends to the project ceiling and loads through host" {
  let host = fake()
  let root = @path.PathValue::new("/workspace", Unix)
  let file = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(file, b"build:\n  echo ok\n")
  let found = try! discover(
    host,
    @path.PathValue::new("/workspace/project", Unix),
    options=SearchOptions::new(ceiling=Some(root)),
  )
  assert_eq(found, file)
  let loaded = try! load(host, file, @source.SourceId::new(9))
  let mut recipe_count = 0
  for item in loaded.ast().items() {
    match item {
      Recipe(recipe) => if recipe.name() == "build" { recipe_count += 1 }
      _ => ()
    }
  }
  assert_eq(recipe_count, 1)
}

///|
test "search accepts dotfile and case-insensitive justfile names" {
  let host = fake()
  let dotfile = @path.PathValue::new("/workspace/.JUSTFILE", Unix)
  host.put_file(dotfile, b"build:\n")
  let found = try! discover(
    host,
    @path.PathValue::new("/workspace/project", Unix),
  )
  assert_eq(found, dotfile)
  assert_eq(
    try! load(host, dotfile, @source.SourceId::new(10)).canonical_path(),
    dotfile,
  )
}

///|
test "search rejects multiple candidate justfiles in one directory" {
  let host = fake()
  host.put_file(@path.PathValue::new("/workspace/justfile", Unix), b"a:\n")
  host.put_file(@path.PathValue::new("/workspace/.justfile", Unix), b"b:\n")
  try discover(host, @path.PathValue::new("/workspace/project", Unix)) catch {
    error => assert_true("\{Repr(error)}".contains("AmbiguousJustfile"))
  } noraise {
    _ => fail("expected ambiguous justfile error")
  }
}

///|
test "explicit missing and capability errors remain typed" {
  let host = fake()
  let missing = @path.PathValue::new("/workspace/nope", Unix)
  try
    discover(host, missing, options=SearchOptions::new(explicit=Some(missing)))
  catch {
    ExplicitFileMissing(path~) => assert_eq(path, missing)
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected explicit missing")
  }
  host.deny(FsRead)
  try discover(host, @path.PathValue::new("/workspace", Unix)) catch {
    LoaderError::Host(_) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected capability error")
  }
}

///|
test "optional imports are skipped and cycles are reported" {
  let host = fake()
  let root = @path.PathValue::new("/workspace/justfile", Unix)
  let child = @path.PathValue::new("/workspace/common.just", Unix)
  host.put_file(
    root, b"import? \"missing.just\"\nimport \"common.just\"\nroot:\n",
  )
  host.put_file(child, b"common:\n")
  let graph = try! load_graph(host, root, @source.SourceId::new(20))
  assert_eq(graph.files().length(), 2)
  assert_eq(graph.files()[1].parent(), Some(root))
  assert_true(graph.files()[1].import_span() is Some(_))
  assert_eq(graph.files()[0].relation(), RootSource)
  assert_eq(graph.files()[1].relation(), ImportedSource)
  assert_true(graph.files()[0].module_path().is_root())
  assert_true(graph.files()[1].module_path().is_root())
  assert_eq(
    graph.files()[1].module_directory(),
    @path.PathValue::new("/workspace", Unix),
  )
  host.put_file(child, b"import \"justfile\"\n")
  try load_graph(host, root, @source.SourceId::new(30)) catch {
    ImportCycle(path~, chain~, span~) => {
      assert_eq(path, root)
      assert_eq(chain, [root, child])
      assert_true(span is Some(_))
    }
    _ => fail("unexpected graph error")
  } noraise {
    _ => fail("expected import cycle")
  }
}

///|
test "relative imports follow source files while cwd follows module ownership" {
  let host = fake()
  let root = @path.PathValue::new("/workspace/justfile", Unix)
  let imported = @path.PathValue::new("/workspace/includes/import.just", Unix)
  let nested = @path.PathValue::new(
    "/workspace/includes/nested/tasks.just",
    Unix,
  )
  let module_file = @path.PathValue::new(
    "/workspace/modules/release/mod.just",
    Unix,
  )
  let module_import = @path.PathValue::new(
    "/workspace/modules/release/shared.just",
    Unix,
  )
  host.put_file(
    root, b"import 'includes/import.just'\nmod release 'modules/release/mod.just'\n",
  )
  host.put_file(imported, b"import 'nested/tasks.just'\n")
  host.put_file(nested, b"nested:\n")
  host.put_file(module_file, b"import 'shared.just'\nrelease:\n")
  host.put_file(module_import, b"shared:\n")
  let files = (try! load_graph(host, root, @source.SourceId::new(50))).files()
  assert_eq(files.length(), 5)
  assert_eq(files[1].path(), imported)
  assert_eq(files[2].path(), nested)
  assert_eq(files[1].relation(), ImportedSource)
  assert_eq(files[2].relation(), ImportedSource)
  assert_eq(
    files[2].module_directory(),
    @path.PathValue::new("/workspace", Unix),
  )
  assert_eq(files[3].path(), module_file)
  assert_eq(files[3].relation(), ModuleSource)
  assert_eq(files[3].module_path().as_string(), "release")
  assert_eq(
    files[3].module_directory(),
    @path.PathValue::new("/workspace/modules/release", Unix),
  )
  assert_eq(files[4].path(), module_import)
  assert_eq(files[4].relation(), ImportedSource)
  assert_eq(files[4].module_path().as_string(), "release")
  assert_eq(files[4].module_directory(), files[3].module_directory())
}

///|
test "graph identity includes module path and implicit modules are unambiguous" {
  let host = fake()
  let root = @path.PathValue::new("/workspace/justfile", Unix)
  let shared = @path.PathValue::new("/workspace/shared.just", Unix)
  host.put_file(root, b"mod alpha 'shared.just'\nmod beta 'shared.just'\n")
  host.put_file(shared, b"task:\n")
  let graph = try! load_graph(host, root, @source.SourceId::new(70))
  assert_eq(graph.files().length(), 3)
  assert_eq(graph.files()[1].canonical_path(), shared)
  assert_eq(graph.files()[2].canonical_path(), shared)
  assert_eq(graph.files()[1].module_path().as_string(), "alpha")
  assert_eq(graph.files()[2].module_path().as_string(), "beta")

  let implicit = @path.PathValue::new("/workspace/foo.just", Unix)
  let nested = @path.PathValue::new("/workspace/foo/justfile", Unix)
  host.put_file(root, b"mod foo\n")
  host.put_file(implicit, b"one:\n")
  host.put_file(nested, b"two:\n")
  try load_graph(host, root, @source.SourceId::new(80)) catch {
    AmbiguousModuleFile(module_name="foo", found~, ..) =>
      assert_eq(found, [implicit, nested])
    error => fail("unexpected implicit module error: \{Repr(error)}")
  } noraise {
    _ => fail("expected ambiguous implicit module")
  }
}

///|
test "symlink canonical identity does not replace the project display parent" {
  let host = fake()
  let link = @path.PathValue::new("/workspace/link/justfile", Unix)
  let target = @path.PathValue::new("/workspace/source/justfile", Unix)
  host.put_file(link, b"build:\n")
  host.set_canonical(link, target)
  let loaded = (try! load_graph(host, link, @source.SourceId::new(60))).files()[0]
  assert_eq(loaded.path(), link)
  assert_eq(loaded.canonical_path(), target)
  assert_eq(
    loaded.module_directory(),
    @path.PathValue::new("/workspace/link", Unix),
  )
}

///|
test "canonical identities collapse symlink-like import aliases" {
  let host = fake()
  let root = @path.PathValue::new("/workspace/justfile", Unix)
  let alias_path = @path.PathValue::new("/workspace/alias.just", Unix)
  let canonical = @path.PathValue::new("/workspace/common.just", Unix)
  host.put_file(root, b"import \"alias.just\"\n")
  host.put_file(alias_path, b"import \"justfile\"\n")
  host.put_file(canonical, b"common:\n")
  host.set_canonical(alias_path, canonical)
  try load_graph(host, root, @source.SourceId::new(40)) catch {
    ImportCycle(path~, chain~, ..) => {
      assert_eq(path, root)
      assert_eq(chain.length(), 2)
    }
    _ => fail("unexpected graph error")
  } noraise {
    _ => fail("expected canonical import cycle")
  }
}

///|
test "global fallback and stdin loading are explicit" {
  let host = fake()
  let global = @path.PathValue::new("/workspace/global.just", Unix)
  host.put_file(global, b"global:\n")
  let found = try! discover(
    host,
    @path.PathValue::new("/workspace/project", Unix),
    options=SearchOptions::new(global=Some(global)),
  )
  assert_eq(found, global)
  let loaded = try! load_stdin(b"stdin:\n", @source.SourceId::new(99))
  assert_eq(loaded.source().name(), "<stdin>")
  assert_eq(loaded.path().as_string(), "<stdin>")
  let markdown = try! load_markdown(
    b"```just\nfrom_markdown:\n```\n",
    @source.SourceId::new(100),
  )
  assert_true(markdown.source().text().contains("from_markdown:"))
}

///|
test "filesystem loading tangles Markdown case insensitively" {
  let host = fake()
  let path = @path.PathValue::new("/workspace/tasks.MD", Unix)
  host.put_file(
    path, b"# prose\n```text\ngarbage[\n```\n```just\nbuild:\n```\n",
  )
  let loaded = try! load(host, path, @source.SourceId::new(1010))
  assert_true(loaded.source().text().contains("build:"))
  assert_false(loaded.source().text().contains("garbage["))
  assert_eq(loaded.source().line_text(6), "build:")
  assert_eq(loaded.module_directory(), @path.PathValue::new("/workspace", Unix))
}

///|
test "in-memory loading follows Markdown extension routing" {
  let loaded = try! load_bytes(
    b"prose\n~~~just\nrelease:\n~~~\n",
    @source.SourceId::new(1011),
    "release.md",
  )
  assert_true(loaded.source().text().contains("release:"))
  assert_false(loaded.source().text().contains("prose"))
}
