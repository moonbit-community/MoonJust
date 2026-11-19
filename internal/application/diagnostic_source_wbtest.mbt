///|
async test "rendering a project error uses the original imported source without another read" {
  let cwd = @path.PathValue::new("/workspace", Unix)
  let root = cwd.join(@path.PathValue::new("justfile", Unix))
  let imported = cwd.join(@path.PathValue::new("rules.just", Unix))
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  // The next root import follows a nested import in depth-first order.
  host.put_file(root, b"import 'tree.just'\nimport 'rules.just'\n")
  host.put_file(
    cwd.join(@path.PathValue::new("tree.just", Unix)),
    b"import 'leaf.just'\n",
  )
  host.put_file(
    cwd.join(@path.PathValue::new("leaf.just", Unix)),
    b"leaf := 'ok'\n",
  )
  host.put_file(imported, b"one := missing_variable\n")
  let arguments = @cli.parse_arguments([], {})
  let context = @project.ProjectInput::new(cwd)
  try
    load_project_snapshot(
      host,
      arguments,
      context,
      @semantic.TargetPlatform::new(Linux, true),
      [],
    )
  catch {
    error => {
      assert_eq(host.source_read_count(), 4)
      host.put_file(imported, b"one := 'replacement'\n")
      let rendered = render_application_error(arguments, context, error)
      assert_true(rendered.contains("rules.just"))
      assert_true(rendered.contains("one := missing_variable"))
      assert_false(rendered.contains("replacement"))
      assert_eq(host.source_read_count(), 4)
    }
  } noraise {
    _ => fail("expected an undefined variable")
  }
}
