///|
async test "explicit Windows converter controls the shell-facing drive path" {
  let cwd = @path.PathValue::new("C:\\work", Windows)
  let platform = @host.PlatformInfo::new(Windows, None, Windows)
  let host = @host_testkit.FakeHost::new(cwd, platform)
  let args = @cli.parse_arguments(["--cygpath", "custom-converter", "run"], {})
  let spec = @host.CommandSpec::new("custom-converter", [
    "--unix",
    cwd.as_string(),
  ])
  spec.set_cwd(cwd)
  spec.set_stdout(Capture)
  spec.set_stderr(Discard)
  host.expect_process(
    spec,
    @host.ProcessResult::new(0, b"/custom/work\r\n", b""),
  )
  let dir = shell_invocation_directory(
    host,
    @workdir.WorkingDirectoryModel::from_stdin(cwd),
    args,
    platform,
  )
  assert_eq(dir.as_string(), "/custom/work")
}
