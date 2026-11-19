///|
async test "path-prefixed recipe discovery stays on the selected UNC share" {
  let server = @path.PathValue::new("//server", Windows)
  let platform = @host.PlatformInfo::new(Windows, None, Windows)
  let host = @host_testkit.FakeHost::new(server, platform)
  let file = @path.PathValue::new("//server/share/justfile", Windows)
  host.put_file(file, b"run:\n  echo ok\n")
  let args = @cli.parse_arguments(["share/../dir/run"], Map([]))
  let (selected, input) = search_prefixed_invocation(
    args,
    @project.ProjectInput::new(server),
  )
  assert_eq(selected.positional(), ["run"])
  assert_eq(input.cwd().as_string(), "\\\\server\\share\\dir")
  host.put_directory(input.cwd())
  let (source, directories) = load_input_with_directories(host, selected, input)
  assert_eq(source.path(), file)
  assert_eq(directories.project_directory().as_string(), "\\\\server\\share")
  let origin = @project.ProjectInput::new(server)
  for
    (argv, expected) in [
      (["--working-directory", "share/../dir"], input.cwd()),
      (["--justfile", "share/../justfile"], file.parent().unwrap()),
    ] {
    let args = @cli.parse_arguments(argv, Map([]))
    let (loaded, dirs) = load_input_with_directories(host, args, origin)
    assert_eq(loaded.path(), file)
    assert_eq(dirs.project_directory(), expected)
    let sources = load_project_sources(host, args, origin)
    assert_eq(sources.directories().justfile(), Some(file))
    assert_eq(sources.directories().project_directory(), expected)
    let interactive = locate_interactive_justfile(host, args, origin)
    assert_eq(interactive.justfile(), Some(file))
    assert_eq(interactive.project_directory(), expected)
  }
  let init = @cli.parse_arguments(["--init", "-f", "share/../new.just"], Map([]))
  ignore(init_response(host, init, origin))
  assert_true(host.file_exists(@path.PathValue::new("//server/share/new.just", Windows)))
}
