///|
test "upstream tempdir::argument_overrides_setting" {
  let project = try! @path.PathValue::new("/workspace/project", @path.Unix)
  let config = try! resolve_temporary_directory(
    project,
    cli_tempdir=Some("cli"),
    setting_tempdir=Some("setting"),
  )
  assert_eq(config.source(), CommandLine)
  assert_eq(config.directory().unwrap().as_string(), "/workspace/project/cli")
}

///|
test "upstream tempdir::setting" {
  let project = try! @path.PathValue::new("/workspace/project", @path.Unix)
  let config = try! resolve_temporary_directory(
    project,
    setting_tempdir=Some("setting"),
  )
  assert_eq(config.source(), Setting)
  assert_eq(
    config.directory().unwrap().as_string(),
    "/workspace/project/setting",
  )
}
