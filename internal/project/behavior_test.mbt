///|
fn project_host() -> @host_testkit.FakeHost raise @path.PathError {
  let cwd = @path.PathValue::new("/workspace", Unix)
  @host_testkit.FakeHost::new(cwd, @host.PlatformInfo::new(Linux, "test", Unix))
}

///|
test "project snapshot owns loading, compilation, and working directories" {
  let host = project_host()
  let root = @path.PathValue::new("/workspace/justfile", Unix)
  host.put_file(root, b"build:\n  echo ok\n")
  let request = ProjectLoadRequest::new(
    ProjectInput::new(@path.PathValue::new("/workspace", Unix)),
    File(root),
    "justfile",
    @semantic.TargetPlatform::new(Linux, true),
    [],
  )
  let snapshot = try! load_snapshot(host, request)
  assert_eq(snapshot.graph().files().length(), 1)
  assert_eq(snapshot.compilation().root().recipe_names(), ["build"])
  assert_eq(snapshot.directories().justfile(), Some(root))
}
