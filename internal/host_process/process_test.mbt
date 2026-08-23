///|
let process_test_mutex : @async.Mutex = Mutex()

///|
#cfg(not(platform="windows"))
fn unix_path(value : String) -> @path.PathValue {
  try! @path.PathValue::new(value, Unix)
}

///|
#cfg(not(platform="windows"))
async test "process adapter preserves cwd env buffered stdin and output" {
  process_test_mutex.acquire()
  defer process_test_mutex.release()
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
  process_test_mutex.acquire()
  defer process_test_mutex.release()
  let failed = try! @host.CommandSpec::new("/bin/sh", ["-c", "exit 7"])
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    failed,
  )
  assert_eq(result.termination(), Exited(7))
}

///|
#cfg(not(platform="windows"))
async test "process adapter maps temporary Windows wrapper failures" {
  process_test_mutex.acquire()
  defer process_test_mutex.release()
  let previous = @env.get_env_var("MOONJUST_OS")
  @env.set_env_var("MOONJUST_OS", "windows")
  defer (match previous {
    Some(value) => @env.set_env_var("MOONJUST_OS", value)
    None => @env.unset_env_var("MOONJUST_OS")
  })
  let command = try! @host.CommandSpec::new("cmd.exe", ["/c", "echo ok"])
  command.set_cwd(unix_path("/moonjust-coverage-no-such-directory"))
  try
    @host.HostAsyncProcess::run_process_async(ProcessAdapter::new(), command)
  catch {
    InvalidInput(message) => assert_true(message.length() > 0)
    error => fail("unexpected wrapper failure: \{Repr(error)}")
  } noraise {
    _ => fail("expected temporary wrapper failure")
  }
}

///|
#cfg(not(platform="windows"))
async test "process adapter tolerates an early child stdin close" {
  process_test_mutex.acquire()
  defer process_test_mutex.release()
  let command = try! @host.CommandSpec::new("/bin/sh", ["-c", "exit 0"])
  command.set_inherit_stdin(false)
  command.set_stdin(@utf8.encode("x".repeat(1024 * 1024)))
  command.set_stdout(Capture)
  command.set_stderr(Capture)
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    command,
  )
  assert_eq(result.termination(), Exited(0))
}

///|
#cfg(not(platform="windows"))
async test "process adapter suppresses shell signal notices" {
  process_test_mutex.acquire()
  defer process_test_mutex.release()
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
  process_test_mutex.acquire()
  defer process_test_mutex.release()
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
  process_test_mutex.acquire()
  defer process_test_mutex.release()
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
  process_test_mutex.acquire()
  defer process_test_mutex.release()
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
  process_test_mutex.acquire()
  defer process_test_mutex.release()
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
