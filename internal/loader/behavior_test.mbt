///|
fn loader_host() -> @host_testkit.FakeHost raise @path.PathError {
  let cwd = @path.PathValue::new("/workspace/project", Unix)
  @host_testkit.FakeHost::new(cwd, @host.PlatformInfo::new(Linux, "test", Unix))
}

///|
test "loader discovers and loads an explicit justfile" {
  let host = loader_host()
  let root = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(root, b"build:\n  echo ok\n")
  assert_eq(
    try! discover(host, host.current_dir(), options=SearchOptions::new()),
    root,
  )
  let loaded = try! load(host, root, @source.SourceId::new(705))
  assert_eq(loaded.path(), root)
  assert_eq(loaded.ast().items().length(), 1)
}

///|
test "loader preserves optional imports and reports cycles" {
  let host = loader_host()
  let root = @path.PathValue::new("/workspace/justfile", Unix)
  let child = @path.PathValue::new("/workspace/common.just", Unix)
  host.put_file(
    root, b"import? \"missing.just\"\nimport \"common.just\"\nroot:\n",
  )
  host.put_file(child, b"common:\n")
  let graph = try! load_graph(host, root, @source.SourceId::new(706))
  assert_eq(graph.files().length(), 2)
  assert_eq(graph.files()[1].parent(), Some(root))
  host.put_file(child, b"import \"justfile\"\n")
  try load_graph(host, root, @source.SourceId::new(707)) catch {
    ImportCycle(path~, ..) => assert_eq(path, root)
    error => fail("unexpected loader error: \{Repr(error)}")
  } noraise {
    _ => fail("expected import cycle")
  }
}
