///|
test "contract JUST-1.57.0-0316 compiler::tests::recursive_includes_fail" {
  let host = @host.FakeHost::new(
    try! @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
  let root = try! @path.PathValue::new("/workspace/justfile", Unix)
  let child = try! @path.PathValue::new("/workspace/subdir/b", Unix)
  host.put_file(root, b"import './subdir/b'\na: b")
  host.put_file(child, b"import '../justfile'\nb:")
  try @loader.load_graph(host, root, @source.SourceId::new(6316)) catch {
    ImportCycle(path~, chain~, ..) => {
      assert_eq(path, root)
      assert_eq(chain, [root, child])
    }
    error => fail("unexpected loader error: \{Repr(error)}")
  } noraise {
    _ => fail("expected recursive import error")
  }
}
