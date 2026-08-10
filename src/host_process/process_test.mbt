///|
fn unix_path(value : String) -> @path.PathValue {
  try! @path.PathValue::new(value, Unix)
}

///|
async test "process adapter preserves cwd env buffered stdin and output" {
  let command = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf '%s|%s|' \"$MODE\" \"$PWD\"; cat",
  ])
  command.set_cwd(unix_path("/tmp"))
  command.set_inherit_environment(false)
  try! command.add_environment("MODE", "test")
  command.set_stdin(b"input")
  command.set_stdout(Capture)
  command.set_stderr(Capture)
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    command,
  )
  assert_eq(result.termination(), Exited(0))
  let output = try! @utf8.decode(result.stdout())
  assert_true(
    output == "test|/tmp|input" || output == "test|/private/tmp|input",
  )
  assert_eq(result.stderr(), b"")
}

///|
async test "process adapter maps nonzero exit termination" {
  let failed = try! @host.CommandSpec::new("/bin/sh", ["-c", "exit 7"])
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    failed,
  )
  assert_eq(result.termination(), Exited(7))
}
