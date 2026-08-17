///|
#cfg(not(platform="windows"))
fn unix_path(value : String) -> @path.PathValue {
  try! @path.PathValue::new(value, Unix)
}

///|
#cfg(not(platform="windows"))
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
#cfg(not(platform="windows"))
async test "process adapter maps nonzero exit termination" {
  let failed = try! @host.CommandSpec::new("/bin/sh", ["-c", "exit 7"])
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    failed,
  )
  assert_eq(result.termination(), Exited(7))
}

///|
#cfg(not(platform="windows"))
async test "process adapter suppresses shell signal notices" {
  let signaled = try! @host.CommandSpec::new("/bin/sh", ["-c", "kill -TERM $$"])
  signaled.set_stdout(Capture)
  signaled.set_stderr(Capture)
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    signaled,
  )
  assert_eq(result.termination(), Signaled(Terminate))
  assert_eq(result.stderr(), b"")
}

///|
#cfg(not(platform="windows"))
async test "discarded streams are drained without being retained" {
  let command = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf ignored; printf warning >&2",
  ])
  command.set_stdout(Discard)
  command.set_stderr(Discard)
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    command,
  )
  assert_eq(result.termination(), Exited(0))
  assert_eq(result.stdout(), b"")
  assert_eq(result.stderr(), b"")
}

///|
#cfg(platform="windows")
async test "Windows process adapter preserves env buffered stdin and output" {
  let command = try! @host.CommandSpec::new("powershell.exe", [
    "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "$value = [Console]::In.ReadToEnd(); [Console]::Out.Write($env:MODE + '|' + $value)",
  ])
  command.set_cwd(try! @path.PathValue::new(".", Windows))
  try! command.add_environment("MODE", "test")
  command.set_stdin(b"input")
  command.set_stdout(Capture)
  command.set_stderr(Capture)
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    command,
  )
  assert_eq(result.termination(), Exited(0))
  assert_eq(result.stdout(), b"test|input")
  assert_eq(result.stderr(), b"")
}

///|
#cfg(platform="windows")
async test "Windows process adapter maps nonzero exit termination" {
  let failed = try! @host.CommandSpec::new("cmd.exe", ["/D", "/C", "exit /B 7"])
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    failed,
  )
  assert_eq(result.termination(), Exited(7))
}

///|
#cfg(platform="windows")
async test "Windows discarded streams are drained without being retained" {
  let command = try! @host.CommandSpec::new("cmd.exe", [
    "/D", "/C", "echo ignored& echo warning 1>&2",
  ])
  command.set_stdout(Discard)
  command.set_stderr(Discard)
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    command,
  )
  assert_eq(result.termination(), Exited(0))
  assert_eq(result.stdout(), b"")
  assert_eq(result.stderr(), b"")
}
