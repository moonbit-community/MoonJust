///|
struct UpstreamDirectoryHost {
  directories : Set[@path.PathValue]
}

///|
fn UpstreamDirectoryHost::new(
  directories : Array[@path.PathValue],
) -> UpstreamDirectoryHost {
  { directories: Set(directories), }
}

///|
impl @host.HostFs for UpstreamDirectoryHost with fn read_file(_self, path) -> Bytes raise @host.HostError {
  raise @host.NotFound(path)
}

///|
impl @host.HostFs for UpstreamDirectoryHost with fn read_file_range(
  _self,
  path,
  _offset,
  _length,
) -> Bytes raise @host.HostError {
  raise @host.NotFound(path)
}

///|
impl @host.HostFs for UpstreamDirectoryHost with fn write_file(
  _self,
  _path,
  _contents,
) -> Unit raise @host.HostError {
  raise @host.InvalidInput("read-only upstream search host")
}

///|
impl @host.HostFs for UpstreamDirectoryHost with fn file_exists(self, path) -> Bool raise @host.HostError {
  self.directories.contains(path)
}

///|
impl @host.HostFs for UpstreamDirectoryHost with fn read_dir(_self, _path) -> Array[
  String,
] raise @host.HostError {
  []
}

///|
impl @host.HostFs for UpstreamDirectoryHost with fn metadata(self, path) -> @host.FileMetadata raise @host.HostError {
  if self.directories.contains(path) {
    @host.FileMetadata::new(false, true, 0L)
  } else {
    raise @host.NotFound(path)
  }
}

///|
impl @host.HostFs for UpstreamDirectoryHost with fn canonicalize(_self, path) -> @path.PathValue raise @host.HostError {
  path
}

///|
impl @host.HostFs for UpstreamDirectoryHost with fn persist_temp_file(
  _self,
  _temporary,
  _destination,
  _overwrite,
) -> Unit raise @host.HostError {
  raise @host.InvalidInput("read-only upstream search host")
}

///|
fn upstream_application_arguments(
  argv : Array[String],
) -> @cli.CliArguments raise @cli.CliParseError {
  @cli.parse_arguments(argv, Map([]))
}

///|
fn upstream_project_input(cwd : String) -> @project.ProjectInput {
  @project.ProjectInput::new(try! @path.PathValue::new(cwd, Unix))
}

///|
fn assert_run_search(
  argv : Array[String],
  expected_cwd : String,
  expected_positionals : Array[String],
) -> Unit raise {
  let arguments = try! upstream_application_arguments(argv)
  let (selected, input) = try! search_prefixed_invocation(
    arguments,
    upstream_project_input("/project/current"),
  )
  assert_eq(input.cwd().as_string(), expected_cwd)
  assert_eq(selected.positional(), expected_positionals)
}

///|
fn assert_upstream_positional(
  argv : Array[String],
  expected_cwd : String,
  expected_overrides : Array[(String, String)],
  expected_arguments : Array[String],
) -> Unit raise {
  let arguments = try! upstream_application_arguments(argv)
  let (selected, input) = try! search_prefixed_invocation(
    arguments,
    upstream_project_input("/project/current"),
  )
  assert_eq(input.cwd().as_string(), expected_cwd)
  assert_eq(selected.variable_overrides(), expected_overrides)
  assert_eq(selected.positional(), expected_arguments)
}

///|
test "upstream positional::tests::no_values" {
  assert_upstream_positional([], "/project/current", [], [])
}

///|
test "upstream positional::tests::arguments_only" {
  assert_upstream_positional(["foo", "bar"], "/project/current", [], [
    "foo", "bar",
  ])
}

///|
test "upstream positional::tests::all_overrides" {
  assert_upstream_positional(
    ["foo=bar", "bar=foo"],
    "/project/current",
    [("foo", "bar"), ("bar", "foo")],
    [],
  )
}

///|
test "upstream positional::tests::no_overrides" {
  assert_upstream_positional(
    ["the-dir/", "baz", "bzzd"],
    "/project/current/the-dir",
    [],
    ["baz", "bzzd"],
  )
}

///|
test "upstream positional::tests::no_search_directory" {
  assert_upstream_positional(
    ["foo=bar", "bar=foo", "baz", "bzzd"],
    "/project/current",
    [("foo", "bar"), ("bar", "foo")],
    ["baz", "bzzd"],
  )
}

///|
test "upstream positional::tests::no_arguments" {
  assert_upstream_positional(
    ["foo=bar", "bar=foo", "the-dir/"],
    "/project/current/the-dir",
    [("foo", "bar"), ("bar", "foo")],
    [],
  )
}

///|
test "upstream positional::tests::all_dot" {
  assert_upstream_positional(
    ["foo=bar", "bar=foo", ".", "garnor"],
    "/project/current",
    [("foo", "bar"), ("bar", "foo")],
    ["garnor"],
  )
}

///|
test "upstream positional::tests::all_dot_dot" {
  assert_upstream_positional(
    ["foo=bar", "bar=foo", "..", "garnor"],
    "/project",
    [("foo", "bar"), ("bar", "foo")],
    ["garnor"],
  )
}

///|
test "upstream positional::tests::all_slash" {
  assert_upstream_positional(
    ["foo=bar", "bar=foo", "/", "garnor"],
    "/",
    [("foo", "bar"), ("bar", "foo")],
    ["garnor"],
  )
}

///|
test "upstream positional::tests::search_directory_after_argument" {
  assert_upstream_positional(
    ["foo=bar", "bar=foo", "baz", "bzzd", "bar/"],
    "/project/current",
    [("foo", "bar"), ("bar", "foo")],
    ["baz", "bzzd", "bar/"],
  )
}

///|
test "upstream positional::tests::override_after_search_directory" {
  assert_upstream_positional(["..", "a=b"], "/project", [], ["a=b"])
}

///|
test "upstream positional::tests::override_after_argument" {
  assert_upstream_positional(["a", "a=b"], "/project/current", [], ["a", "a=b"])
}

///|
test "upstream config::tests::search_config_default" {
  let arguments = try! upstream_application_arguments([])
  assert_eq(try! input_selection(arguments, Unix), @cli.InputSelection::Search)
}

///|
test "upstream config::tests::search_config_from_working_directory_and_justfile" {
  let arguments = try! upstream_application_arguments([
    "--working-directory", "foo", "--justfile", "bar",
  ])
  assert_eq(
    try! input_selection(arguments, Unix),
    @cli.InputSelection::File(try! @path.PathValue::new("bar", Unix)),
  )
  assert_eq(
    (try! working_directory_argument(arguments, Unix)).map(fn(path) {
      path.as_string()
    }),
    Some("foo"),
  )
}

///|
test "upstream config::tests::search_config_justfile_stdin_long" {
  let arguments = try! upstream_application_arguments(["--justfile", "-"])
  assert_eq(try! input_selection(arguments, Unix), @cli.InputSelection::Stdin)
  assert_true((try! working_directory_argument(arguments, Unix)) is None)
}

///|
test "upstream config::tests::search_config_justfile_stdin_short" {
  let arguments = try! upstream_application_arguments(["-f", "-"])
  assert_eq(try! input_selection(arguments, Unix), @cli.InputSelection::Stdin)
  assert_true((try! working_directory_argument(arguments, Unix)) is None)
}

///|
test "upstream config::tests::search_config_justfile_stdin_with_working_directory" {
  let arguments = try! upstream_application_arguments([
    "--justfile", "-", "--working-directory", "foo",
  ])
  assert_eq(try! input_selection(arguments, Unix), @cli.InputSelection::Stdin)
  assert_eq(
    (try! working_directory_argument(arguments, Unix)).map(fn(path) {
      path.as_string()
    }),
    Some("foo"),
  )
}

///|
test "upstream config::tests::search_directory_parent" {
  assert_run_search(["../"], "/project", [])
}

///|
test "upstream config::tests::search_directory_parent_with_recipe" {
  assert_run_search(["../build"], "/project", ["build"])
}

///|
test "upstream config::tests::search_directory_child" {
  assert_run_search(["foo/"], "/project/current/foo", [])
}

///|
test "upstream config::tests::search_directory_deep" {
  assert_run_search(["foo/bar/"], "/project/current/foo/bar", [])
}

///|
test "upstream config::tests::search_directory_child_with_recipe" {
  assert_run_search(["foo/build"], "/project/current/foo", ["build"])
}

///|
test "upstream config::tests::search_directory_conflict_justfile" {
  let arguments = try! upstream_application_arguments([
    "--justfile", "bar", "foo/build",
  ])
  let message = try
    search_prefixed_invocation(
      arguments,
      upstream_project_input("/project/current"),
    )
  catch {
    Query(message) => message
    _ => "wrong error"
  } noraise {
    _ => "no error"
  }
  assert_eq(
    message, "path-prefixed recipes may not be used with `--global-justfile`, `--working-directory`, or `--justfile`",
  )
}

///|
test "upstream config::tests::search_directory_conflict_working_directory" {
  let arguments = try! upstream_application_arguments([
    "--justfile", "bar", "--working-directory", "baz", "foo/build",
  ])
  let message = try
    search_prefixed_invocation(
      arguments,
      upstream_project_input("/project/current"),
    )
  catch {
    Query(message) => message
    _ => "wrong error"
  } noraise {
    _ => "no error"
  }
  assert_eq(
    message, "path-prefixed recipes may not be used with `--global-justfile`, `--working-directory`, or `--justfile`",
  )
}

///|
test "upstream config::tests::subcommand_list_search_directory" {
  let input = upstream_project_input("/project/current")
  let host = UpstreamDirectoryHost::new([
    try! @path.PathValue::new("/project", Unix),
  ])
  let arguments = try! upstream_application_arguments(["--list", ".."])
  let (selected, selected_input) = try! query_search_prefix(
    host, arguments, input,
  )
  assert_eq(selected_input.cwd().as_string(), "/project")
  assert_true(selected.positional().is_empty())
}

///|
test "upstream config::tests::subcommand_show_search_directory" {
  let input = upstream_project_input("/project/current")
  let host = UpstreamDirectoryHost::new([])
  let arguments = try! upstream_application_arguments(["--show", "../foo"])
  let (selected, selected_input) = try! query_search_prefix(
    host, arguments, input,
  )
  assert_eq(selected_input.cwd().as_string(), "/project")
  assert_eq(selected.positional(), ["foo"])
}
