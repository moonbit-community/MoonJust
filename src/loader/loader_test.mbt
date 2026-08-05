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
  host.put_file(child, b"import \"justfile\"\n")
  try load_graph(host, root, @source.SourceId::new(30)) catch {
    ImportCycle(path~) => assert_eq(path, root)
    _ => fail("unexpected graph error")
  } noraise {
    _ => fail("expected import cycle")
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
}
