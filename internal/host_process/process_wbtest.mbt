///|
#cfg(all(target="native", not(platform="windows")))
async test "signal status keeps the direct child result without a fixed registry" {
  assert_eq(signal_process_status(0), 0)
  assert_eq(signal_process_status(-15), -15)
}

///|
#cfg(all(target="native", not(platform="windows")))
test "process group helper validates payload without taking process ownership" {
  assert_eq(process_group_exec_ffi(b"", 0), 22)
  assert_eq(process_group_exec_ffi(b"\x00", 1), 22)
  assert_eq(
    process_group_payload(["a b", "", "c\\d"][:]),
    b"a b\x00\x00c\\d\x00",
  )
}

///|
test "process status mapping retains only captured streams" {
  let captured = try! @host.CommandSpec::new("echo", [])
  captured.set_stdout(Capture)
  captured.set_stderr(Capture)
  assert_eq(
    process_result(captured, 0, b"out", b"err", false),
    @host.ProcessResult::new(0, b"out", b"err"),
  )
  assert_eq(
    process_result(captured, -15, b"out", b"err", false).termination(),
    Signaled(Terminate),
  )
  assert_eq(
    process_result(captured, -257, b"out", b"err", false).termination(),
    Interrupted(Hangup),
  )
  let discarded = try! @host.CommandSpec::new("echo", [])
  discarded.set_stdout(Discard)
  discarded.set_stderr(Discard)
  assert_eq(
    process_result(discarded, 143, b"out", b"err", true),
    @host.ProcessResult::from_signal(Terminate, b"", b""),
  )
}

///|
test "process result helpers normalize signals and command environments" {
  assert_eq(signal_from_number(1), Hangup)
  assert_eq(signal_from_number(2), Interrupt)
  assert_eq(signal_from_number(15), Terminate)
  assert_eq(signal_from_number(99), OtherSignal(99))
  assert_eq(signal_from_status(-2), Interrupt)
  let command = try! @host.CommandSpec::new("echo", [])
  try! command.add_environment("A", "1")
  try! command.add_environment("B", "2")
  assert_eq(environment_map(command), { "A": "1", "B": "2" })
}

///|
async test "process output limits reject negative and oversized captures" {
  let invalid = try! @host.CommandSpec::new("echo", [])
  try run_process_with_output_limit(invalid, -1) catch {
    InvalidInput(message) =>
      assert_eq(message, "captured process output limit must be non-negative")
    _error => fail("unexpected output-limit error")
  } noraise {
    _ => fail("expected negative output limit to fail")
  }
  let oversized = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf 0123456789",
  ])
  oversized.set_stdout(Capture)
  try run_process_with_output_limit(oversized, 3) catch {
    InvalidInput(message) =>
      assert_true(message.contains("exceeded the 3-byte"))
    _error => fail("unexpected capture-limit error")
  } noraise {
    _ => fail("expected oversized capture to fail")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
test "native process classification recognizes supported shells" {
  for program in ["sh", "BASH", "/usr/bin/dash", "fish"] {
    assert_true(is_shell_program(program))
  }
  assert_false(is_shell_program("python"))
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "Windows command materializer rewrites cmd scripts and cleans paths" {
  let previous = @env.get_env_var("MOONJUST_OS")
  @env.set_env_var("MOONJUST_OS", "windows")
  defer (match previous {
    Some(value) => @env.set_env_var("MOONJUST_OS", value)
    None => @env.unset_env_var("MOONJUST_OS")
  })
  let (program, arguments, temporary) = try! materialize_windows_command(
    "cmd.exe",
    ["/d", "/c", "echo %MISSING%"],
    ".",
    [],
    false,
  )
  assert_eq(program, "cmd.exe")
  assert_eq(arguments[0], "/d")
  assert_eq(arguments[1], "/s")
  assert_eq(arguments[2], "/c")
  guard temporary is Some(path) else {
    fail("expected temporary command script")
  }
  try @async_fs.remove(path) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
#cfg(not(target="wasm"))
test "native observable command leaves programs unchanged" {
  assert_eq(observable_process_command("echo", ["ok"]), ("echo", ["ok"], false))
}

///|
#cfg(target="wasm")
test "wasm observable command wraps shells and temporary just scripts" {
  assert_eq(observable_process_command("echo", ["ok"]), ("echo", ["ok"], false))
  let wrapped = observable_process_command("sh", ["-c", "echo ok"])
  assert_eq(wrapped.0, "/bin/sh")
  assert_true(wrapped.2)
  assert_true(wrapped.1.contains("sh"))
  let temporary = observable_process_command("/tmp/just-script", [])
  assert_eq(temporary.0, "/bin/sh")
  assert_true(temporary.2)
}
