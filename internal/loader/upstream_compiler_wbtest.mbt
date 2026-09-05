///|
fn upstream_module(
  name : String,
  path : String?,
  source : @source.SourceId,
) -> @syntax.Module {
  let span = @source.Span::origin(source)
  let literal = path.map(fn(value) {
    @syntax.StringLiteral::new(value, value, Raw, span)
  })
  @syntax.Module::new(name, span, literal, false, span)
}

///|
test "upstream compiler::tests::find_module_file" {
  let root = try! @path.PathValue::new("/workspace", Unix)
  let source = try! root.join(@path.PathValue::new("justfile", Unix))
  let host = @host_testkit.FakeHost::new(
    root,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let direct = try! root.join(@path.PathValue::new("foo.just", Unix))
  host.put_file(direct, b"")
  assert_eq(
    try! resolve_module_file(
      host,
      source,
      upstream_module("foo", None, @source.SourceId::new(966)),
    ).unwrap(),
    direct,
  )
  let directory = try! root.join(@path.PathValue::new("bar", Unix))
  host.put_directory(directory)
  let nested = try! directory.join(@path.PathValue::new("justfile", Unix))
  host.put_file(nested, b"")
  assert_eq(
    try! resolve_module_file(
      host,
      source,
      upstream_module("bar", None, @source.SourceId::new(967)),
    ).unwrap(),
    nested,
  )
  let ambiguous = try! root.join(@path.PathValue::new("amb.just", Unix))
  host.put_file(ambiguous, b"")
  let ambiguous_dir = try! root.join(@path.PathValue::new("amb", Unix))
  host.put_directory(ambiguous_dir)
  let ambiguous_nested = try! ambiguous_dir.join(
    @path.PathValue::new("mod.just", Unix),
  )
  host.put_file(ambiguous_nested, b"")
  try
    ignore(
      resolve_module_file(
        host,
        source,
        upstream_module("amb", None, @source.SourceId::new(968)),
      ),
    )
  catch {
    AmbiguousModuleFile(module_name~, found~, ..) => {
      assert_eq(module_name, "amb")
      assert_eq(found.length(), 2)
    }
    error => fail("unexpected module resolution error: \{Repr(error)}")
  } noraise {
    _ => fail("expected ambiguous module file")
  }
}
