///|
test "upstream global::not_macos" {
  let cwd = try! @path.PathValue::new("/workspace", @path.Unix)
  let config = try! @path.PathValue::new("/config", @path.Unix)
  let global_dir = try! config.join(
    try! @path.PathValue::new("just", @path.Unix),
  )
  let justfile = try! global_dir.join(
    try! @path.PathValue::new("justfile", @path.Unix),
  )
  let host = @host_testkit.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(@host.Linux, "test", @path.Unix),
  )
  host.put_directory(config)
  host.put_directory(global_dir)
  host.put_file(justfile, b"default:\n    echo foo\n")
  host.set_env("HOME", "/home/test")
  host.set_env("XDG_CONFIG_HOME", "/config")
  let arguments = try! @cli.parse_arguments(["--global-justfile"], Map([]))
  let context = @project.ProjectInput::new(cwd)
  let resolved = try! resolve_global_context(host, host, arguments, context)
  assert_eq(resolved.global_justfile(), Some(justfile))
  assert_eq(resolved.global_project_directory(), Some(cwd))
}
