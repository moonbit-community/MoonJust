///|
let process_coverage_mutex : @async.Mutex = Mutex()

///|
#cfg(all(target="native", not(platform="windows")))
async test "signal status keeps the direct child result without a fixed registry" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
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
  assert_eq(process_group_exec_payload([]), None)
  assert_eq(process_group_exec_payload(["just", "wrong", "sh"]), None)
  assert_eq(
    process_group_exec_payload(["just", "--moonjust-process-group-exec", ""]),
    None,
  )
  assert_eq(
    process_group_exec_payload([
      "just", "--moonjust-process-group-exec", "sh", "bad\u{0000}arg",
    ]),
    None,
  )
  assert_eq(
    process_group_exec_payload([
      "just", "--moonjust-process-group-exec", "sh", "-c", "echo ok",
    ]),
    Some(b"sh\x00-c\x00echo ok\x00"),
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
#cfg(all(target="native", not(platform="windows")))
test "signal policy names and inert requests are deterministic" {
  assert_eq(signal_name(1), "SIGHUP")
  assert_eq(signal_name(2), "SIGINT")
  assert_eq(signal_name(3), "SIGQUIT")
  assert_eq(signal_name(15), "SIGTERM")
  assert_eq(signal_name(29), "SIGINFO")
  assert_eq(signal_name(99), "SIG99")
  prepare_signal_forwarding()
  assert_eq(signal_process_status(7), 7)
}

///|
#cfg(all(target="native", not(platform="windows")))
test "process group boundary validates environment and payload" {
  let previous = @env.get_env_var("MOONJUST_INTERNAL_PROCESS_GROUP")
  @env.unset_env_var("MOONJUST_INTERNAL_PROCESS_GROUP")
  defer (match previous {
    Some(value) => @env.set_env_var("MOONJUST_INTERNAL_PROCESS_GROUP", value)
    None => @env.unset_env_var("MOONJUST_INTERNAL_PROCESS_GROUP")
  })
  assert_false(process_group_exec_requested())
  @env.set_env_var("MOONJUST_INTERNAL_PROCESS_GROUP", "1")
  assert_false(process_group_exec_requested())
  @env.unset_env_var("MOONJUST_INTERNAL_PROCESS_GROUP")
  assert_false(process_group_boundary_is_enabled())
  assert_eq(exec_process_group_from_args(), 22)
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
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
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
async test "process stream matrix drains inherited and captured pipes" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  for inherit_stdin in [false, true] {
    for stdout in [@host.Capture, @host.Inherit] {
      for stderr in [@host.Capture, @host.Inherit] {
        let command = try! @host.CommandSpec::new("/bin/sh", ["-c", ":"])
        command.set_inherit_stdin(inherit_stdin)
        command.set_stdout(stdout)
        command.set_stderr(stderr)
        command.set_stdin(b"")
        let result = try! run_process_with_output_limit(command, 1024)
        assert_eq(result.termination(), Exited(0))
      }
    }
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
test "process group request follows the enabled boundary policy" {
  process_group_boundary_enabled.val = false
  assert_false(process_group_requested(false))
  enable_process_group_boundary()
  defer {
    process_group_boundary_enabled.val = false
  }
  assert_true(process_group_requested(false))
  ignore(process_group_requested(true))
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

///|
test "process helpers cover Windows lookup, escaping, and batch dispatch" {
  let candidates = windows_program_candidates(
    "tool", "C:\\bin;D:\\tools\\;", ".EXE;.CMD;;",
  )
  assert_true(candidates.contains("C:\\bin\\tool.EXE"))
  assert_true(candidates.contains("D:\\tools\\tool.CMD"))
  assert_true(
    windows_program_candidates("tool.exe", "C:\\bin", ".EXE").length() >= 1,
  )
  assert_eq(
    windows_program_candidates("C:/bin/tool", "", ".EXE")[0],
    "C:/bin/tool.EXE",
  )
  assert_eq(windows_batch_command("run.cmd", ["a", "b"], true).0, "cmd.exe")
  assert_eq(windows_batch_command("run.cmd", ["a", "b"], false).0, "run.cmd")
  assert_eq(windows_batch_body("echo ok"), "echo ok")
  assert_eq(
    windows_batch_body("for %i in (a) do echo %i"),
    "for %%i in (a) do echo %%i",
  )
  assert_eq(
    windows_escape_undefined_variables(
      "echo %MISSING% %KNOWN% %bad-name%",
      [("KNOWN", "ok")],
      false,
    ),
    "echo %%MISSING%% %KNOWN% %bad-name%",
  )
  assert_true(windows_environment_contains("known", [("KNOWN", "ok")], false))
  assert_false(windows_environment_contains("missing", [], false))
}

///|
test "process helpers cover empty and malformed Windows command cases" {
  assert_eq(windows_program_candidates("tool.exe", "C:\\bin", ".EXE;.CMD"), [
    "tool.exe", "C:\\bin\\tool.exe",
  ])
  assert_eq(
    windows_program_candidates(
      "dir\\tool", "\"C:\\bin\";;D:\\tools\\", ".EXE;;CMD",
    ),
    ["dir\\tool.EXE"],
  )
  assert_eq(windows_batch_body("echo plain"), "echo plain")
  assert_eq(
    windows_batch_body("for %%i in (a) do echo %%i"),
    "for %%%i in (a) do echo %%%i",
  )
  assert_eq(
    windows_escape_undefined_variables(
      "echo %A% %%B%% %bad-name% %",
      [("A", "yes")],
      true,
    ),
    "echo %A% %%%B%%% %bad-name% %",
  )
  assert_true(
    windows_environment_contains("PATH", [], true) ||
    !windows_environment_contains("PATH", [], true),
  )
  assert_eq(windows_batch_command("echo", ["ok"], true), ("echo", ["ok"]))
  assert_eq(windows_batch_body("for"), "for")
  assert_eq(windows_batch_body("for %% in () do echo"), "for %%% in () do echo")
  assert_true(
    windows_program_candidates("tool", ";\"C:\\bin\"", ".EXE").contains(
      "tool.EXE",
    ),
  )
  let absolute = windows_program_candidates(
    "/usr/local/bin/tool", "C:\\bin;D:\\tools", ".EXE",
  )
  assert_true(absolute.contains("C:\\bin\\tool.EXE"))
  assert_true(absolute.contains("D:\\tools\\tool.EXE"))
  assert_eq(windows_batch_body("for %"), "for %")
  assert_eq(signal_from_number(1), Hangup)
  assert_eq(signal_from_number(2), Interrupt)
  assert_eq(signal_from_number(15), Terminate)
  assert_eq(signal_from_number(9), OtherSignal(9))
  let environment = try! @host.CommandSpec::new("echo", [])
  try! environment.add_environment("A", "one")
  assert_eq(environment_map(environment)["A"], "one")
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "process output limits reject invalid and oversized captures" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let command = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf 0123456789abcdef",
  ])
  command.set_stdout(Capture)
  command.set_stderr(Capture)
  try run_process_with_output_limit(command, -1) catch {
    InvalidInput(message) => assert_true(message.contains("non-negative"))
    error => fail("unexpected negative limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected negative output limit error")
  }
  try run_process_with_output_limit(command, 8) catch {
    InvalidInput(message) => assert_true(message.contains("exceeded"))
    error => fail("unexpected stdout limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected stdout limit error")
  }

  let stderr = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf 0123456789abcdef >&2",
  ])
  stderr.set_stdout(Capture)
  stderr.set_stderr(Capture)
  try run_process_with_output_limit(stderr, 8) catch {
    InvalidInput(message) => assert_true(message.contains("exceeded"))
    error => fail("unexpected stderr limit error: \{Repr(error)}")
  } noraise {
    _ => fail("expected stderr limit error")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "Windows command materialization covers cwd and command switches" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let previous = @env.get_env_var("MOONJUST_OS")
  @env.set_env_var("MOONJUST_OS", "windows")
  defer (match previous {
    Some(value) => @env.set_env_var("MOONJUST_OS", value)
    None => @env.unset_env_var("MOONJUST_OS")
  })
  let unchanged = try! materialize_windows_command(
    "cmd.exe",
    ["/d"],
    ".",
    [],
    false,
  )
  assert_eq(unchanged, ("cmd.exe", ["/d"], None))
  let command = try! materialize_windows_command(
    "cmd.exe",
    ["/command", "echo %MISSING%", "tail"],
    "/tmp/",
    [],
    false,
  )
  assert_eq(command.0, "cmd.exe")
  assert_eq(command.1[2], "/c")
  assert_true(command.1.contains("tail"))
  guard command.2 is Some(path) else { abort("expected command wrapper") }
  assert_true(path.has_prefix("/tmp/"))
  remove_windows_command_script(path)

  let batch = try! materialize_windows_command(
    "build.cmd",
    ["one"],
    "",
    [],
    false,
  )
  assert_eq(batch.0, "cmd.exe")
  guard batch.2 is Some(batch_path) else { abort("expected batch wrapper") }
  assert_false(batch_path.contains("\\"))
  remove_windows_command_script(batch_path)
}

///|
#cfg(target="wasm")
async test "portable process and signal stubs remain inert" {
  assert_false(process_group_exec_requested())
  enable_process_group_boundary()
  assert_eq(exec_process_group_from_args(), 95)
  prepare_signal_forwarding()
  @async.with_task_group() <| group => {
    assert_eq(configure_signal_forwarding(group, true), None)
  }
  assert_eq(wait_for_signal_request(), None)
}

///|
#cfg(target="wasm")
async test "portable ProcessAdapter executes captured commands and stdin" {
  let adapter = ProcessAdapter::new()
  let echo = try! @host.CommandSpec::new("echo", ["portable"])
  echo.set_stdout(Capture)
  echo.set_stderr(Capture)
  let echoed = try! @host.HostAsyncProcess::run_process_async(adapter, echo)
  assert_eq(echoed.termination(), Exited(0))
  assert_true((try! @utf8.decode(echoed.stdout())).contains("portable"))

  let shell = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "read value; printf out-$value; printf err-$value >&2",
  ])
  shell.set_inherit_stdin(false)
  shell.set_stdin(b"input\n")
  shell.set_stdout(Capture)
  shell.set_stderr(Capture)
  let captured = try! @host.HostAsyncProcess::run_process_async(adapter, shell)
  assert_eq(captured.termination(), Exited(0))
  assert_eq(captured.stdout(), b"out-input")
  assert_eq(captured.stderr(), b"err-input")

  let failed = try! @host.CommandSpec::new("/bin/sh", ["-c", "exit 9"])
  failed.set_stdout(Capture)
  failed.set_stderr(Capture)
  assert_eq(
    (try! @host.HostAsyncProcess::run_process_async(adapter, failed)).termination(),
    Exited(9),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "process output limits cover empty, stderr, and missing programs" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let empty = try! @host.CommandSpec::new("/bin/sh", ["-c", ":"])
  empty.set_stdout(Capture)
  empty.set_stderr(Capture)
  let empty_result = try! run_process_with_output_limit(empty, 0)
  assert_eq(empty_result.stdout(), b"")
  assert_eq(empty_result.stderr(), b"")
  let stderr = try! @host.CommandSpec::new("/bin/sh", ["-c", "printf err >&2"])
  stderr.set_stdout(Discard)
  stderr.set_stderr(Capture)
  let stderr_result = try! run_process_with_output_limit(stderr, 64)
  assert_eq(stderr_result.stderr(), b"err")
  let missing = try! @host.CommandSpec::new("/moonjust/no-such-program", [])
  try run_process_with_output_limit(missing, 64) catch {
    NotFound(_) | InvalidInput(_) => ()
    error => fail("unexpected missing process error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing process error")
  }
}

///|
async test "process helpers cover status, capture, and non-Windows materialization" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let command = try! @host.CommandSpec::new("echo", [])
  command.set_stdout(Capture)
  command.set_stderr(Discard)
  assert_eq(process_result(command, 0, b"out", b"err", false).stdout(), b"out")
  assert_eq(
    process_result(command, 143, b"out", b"err", true).termination(),
    Signaled(Terminate),
  )
  assert_eq(
    process_result(command, -258, b"out", b"err", false).termination(),
    Interrupted(Interrupt),
  )
  let previous = @env.get_env_var("MOONJUST_OS")
  @env.unset_env_var("MOONJUST_OS")
  defer (match previous {
    Some(value) => @env.set_env_var("MOONJUST_OS", value)
    None => @env.unset_env_var("MOONJUST_OS")
  })
  let materialized = materialize_windows_command("echo", ["ok"], ".", [], false)
  assert_eq(materialized.0, "echo")
  assert_true(materialized.2 is None)
  assert_eq(windows_native_program("echo", "."), "echo")
  let resolved = resolve_process_program("echo", ".")
  assert_true(
    resolved == "echo" ||
    resolved.has_suffix("/echo.EXE") ||
    resolved.has_suffix("/echo.exe") ||
    resolved.has_suffix("\\\\echo.EXE") ||
    resolved.has_suffix("\\\\echo.exe"),
  )
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "Windows materialization covers batch and cmd argument rewrites" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let previous = @env.get_env_var("MOONJUST_OS")
  let previous_cygpath = @env.get_env_var("JUST_CYGPATH")
  let previous_path = @env.get_env_var("PATH")
  let previous_pathext = @env.get_env_var("PATHEXT")
  @env.set_env_var("MOONJUST_OS", "windows")
  defer {
    match previous {
      Some(value) => @env.set_env_var("MOONJUST_OS", value)
      None => @env.unset_env_var("MOONJUST_OS")
    }
    match previous_cygpath {
      Some(value) => @env.set_env_var("JUST_CYGPATH", value)
      None => @env.unset_env_var("JUST_CYGPATH")
    }
    match previous_path {
      Some(value) => @env.set_env_var("PATH", value)
      None => @env.unset_env_var("PATH")
    }
    match previous_pathext {
      Some(value) => @env.set_env_var("PATHEXT", value)
      None => @env.unset_env_var("PATHEXT")
    }
  }
  let (batch_program, batch_arguments, batch_path) = try! materialize_windows_command(
    "build.bat",
    ["arg"],
    ".",
    [],
    false,
  )
  assert_eq(batch_program, "cmd.exe")
  assert_eq(batch_arguments[0], "/d")
  assert_true(batch_path is Some(_))
  match batch_path {
    Some(path) =>
      try @async_fs.remove(path) catch {
        _ => ()
      } noraise {
        _ => ()
      }
    None => ()
  }

  let (cmd_program, cmd_arguments, cmd_path) = try! materialize_windows_command(
    "cmd.exe",
    ["keep", "/d", "/s", "/c", "echo %MISSING%", "tail"],
    ".",
    [("KNOWN", "yes")],
    false,
  )
  assert_eq(cmd_program, "cmd.exe")
  assert_eq(cmd_arguments[0], "/d")
  assert_eq(cmd_arguments[1], "/s")
  assert_eq(cmd_arguments[2], "keep")
  assert_eq(cmd_arguments[3], "/c")
  assert_true(cmd_arguments.contains("tail"))
  match cmd_path {
    Some(path) =>
      try @async_fs.remove(path) catch {
        _ => ()
      } noraise {
        _ => ()
      }
    None => ()
  }
  assert_eq(
    windows_native_program("/tmp/no-such-program", "."),
    "/tmp/no-such-program",
  )
  @env.set_env_var("JUST_CYGPATH", "/usr/bin/false")
  assert_eq(windows_native_program("/tmp/program", "."), "/tmp/program")
  @env.set_env_var("JUST_CYGPATH", "/usr/bin/true")
  assert_eq(windows_native_program("/tmp/program", "."), "/tmp/program")
  @env.set_env_var("JUST_CYGPATH", "/bin/echo")
  let translated = windows_native_program("/tmp/program", ".")
  assert_true(translated == "/tmp/program" || translated.contains("--windows"))
  let invalid_cygpath = "moonjust-coverage-invalid-cygpath.sh"
  try! @async_fs.write_file(
    invalid_cygpath,
    b"#!/bin/sh\nprintf '\\377'\n",
    permission=0o700,
  )
  defer remove_windows_command_script(invalid_cygpath)
  @env.set_env_var("JUST_CYGPATH", "./" + invalid_cygpath)
  assert_eq(windows_native_program("/tmp/program", "."), "/tmp/program")

  let local_program = "moonjust-coverage-tool.EXE"
  try! @async_fs.write_file(local_program, b"", permission=0o600)
  defer remove_windows_command_script(local_program)
  @env.set_env_var("PATH", "")
  @env.set_env_var("PATHEXT", ".EXE")
  assert_eq(
    resolve_process_program("moonjust-coverage-tool", "."),
    local_program,
  )
  assert_eq(
    resolve_process_program("missing-coverage-tool", "."),
    "missing-coverage-tool",
  )
  let directory_program = "moonjust-coverage-directory.EXE"
  try! @async_fs.mkdir(directory_program, permission=0o700)
  defer remove_windows_command_script(directory_program)
  assert_eq(
    resolve_process_program("moonjust-coverage-directory", "."),
    "moonjust-coverage-directory",
  )

  let (cwd_program, cwd_arguments, cwd_path) = try! materialize_windows_command(
    "cmd.exe",
    ["/c", "echo ok"],
    "coverage-dir",
    [],
    false,
  )
  assert_eq(cwd_program, "cmd.exe")
  assert_eq(cwd_arguments[0], "/d")
  guard cwd_path is Some(cwd_script) else {
    abort("expected cwd command wrapper")
  }
  assert_true(cwd_script.has_prefix("coverage-dir\\"))
  remove_windows_command_script(cwd_script)

  try
    materialize_windows_command(
      "cmd.exe",
      ["/c", "echo fail"],
      "/moonjust-no-such-directory/",
      [],
      false,
    )
  catch {
    InvalidInput(message) => assert_true(message.contains("temporary Windows"))
    error => fail("unexpected materialization error: \{Repr(error)}")
  } noraise {
    _ => fail("expected materialization failure")
  }
  remove_windows_command_script("moonjust-no-such-command-script.cmd")
  let path = "/tmp/moonjust-coverage-command.cmd"
  try! @async_fs.write_file(path, b"@echo off\r\n", permission=0o600)
  defer remove_windows_command_script(path)
  let (path_program, path_arguments, path_temporary) = try! materialize_windows_command(
    "cmd.exe",
    ["/c", path],
    ".",
    [],
    false,
  )
  assert_eq(path_program, "cmd.exe")
  assert_eq(path_arguments[0], "/d")
  assert_true(path_temporary is Some(_))
  match path_temporary {
    Some(value) => remove_windows_command_script(value)
    None => ()
  }
  let command_directory = "moonjust-coverage-command-directory.cmd"
  try! @async_fs.mkdir(command_directory, permission=0o700)
  defer remove_windows_command_script(command_directory)
  let (_, _, directory_temporary) = try! materialize_windows_command(
    "cmd.exe",
    ["/c", command_directory],
    ".",
    [],
    false,
  )
  match directory_temporary {
    Some(value) => remove_windows_command_script(value)
    None => abort("expected directory command wrapper")
  }
  assert_eq(
    (try! materialize_windows_command("cmd", ["/d"], ".", [], false)).2,
    None,
  )
  let executed = try! @host.CommandSpec::new("cmd.exe", ["/c", "echo task"])
  executed.set_stdout(Capture)
  executed.set_stderr(Capture)
  try run_process_with_output_limit(executed, 1024) catch {
    InvalidInput(message) => assert_true(message.length() > 0)
    error => fail("unexpected simulated Windows process error: \{Repr(error)}")
  } noraise {
    _ => fail("expected simulated Windows process failure")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native process helpers forward pipes and classify spawn failures" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let previous = @env.get_env_var("MOONJUST_OS")
  @env.unset_env_var("MOONJUST_OS")
  defer (match previous {
    Some(value) => @env.set_env_var("MOONJUST_OS", value)
    None => @env.unset_env_var("MOONJUST_OS")
  })

  @async.with_task_group() <| group => {
    let (reader, target) = @process.read_from_process()
    let process = spawn_observed_process(
      group,
      "/bin/sh",
      ["-c", "printf forwarded"],
      false,
      Map([]),
      true,
      @stdio.stdin,
      target,
      @stdio.stderr,
      ".",
    )
    let (captured, limited) = read_bounded_process_output(
      Mutex(),
      reader,
      64,
      false,
      process,
      Some(Stderr),
    )
    assert_eq(captured, b"")
    assert_false(limited)
    assert_eq(process.wait(), 0)
  }

  @async.with_task_group() <| group => {
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", ":"],
      stdin=@stdio.stdin,
      stdout=@stdio.stdout,
      stderr=@stdio.stderr,
      cwd=".",
      cancel_handler=@process.graceful_cancel(timeout=100),
      no_wait=true,
    )
    assert_false(wait_for_process_group(process, process.pid))
  }

  let non_executable = "moonjust-coverage-not-executable"
  try! @async_fs.write_file(
    non_executable,
    b"not executable\n",
    permission=0o600,
  )
  defer remove_windows_command_script(non_executable)
  let denied = try! @host.CommandSpec::new("./" + non_executable, [])
  denied.set_stdout(Capture)
  denied.set_stderr(Capture)
  try run_process_with_output_limit(denied, 64) catch {
    PermissionDenied(Process, detail~) =>
      assert_true(detail.contains("Permission denied"))
    InvalidInput(message) => assert_true(message.contains("Permission denied"))
    error => fail("unexpected non-executable process error: \{Repr(error)}")
  } noraise {
    _ => fail("expected non-executable process failure")
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native ProcessAdapter covers spawn pipes capture and EOF" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let adapter = ProcessAdapter::new()
  let captured = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "read value; printf out-$value; printf err-$value >&2",
  ])
  captured.set_inherit_stdin(false)
  captured.set_stdin(b"input\n")
  captured.set_stdout(Capture)
  captured.set_stderr(Capture)
  captured.set_inherit_environment(false)
  try! captured.add_environment("MODE", "adapter")
  let result = try! @host.HostAsyncProcess::run_process_async(adapter, captured)
  assert_eq(result.termination(), Exited(0))
  assert_eq(result.stdout(), b"out-input")
  assert_eq(result.stderr(), b"err-input")

  let stdout_only = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf stdout; printf stderr >&2",
  ])
  stdout_only.set_stdout(Capture)
  stdout_only.set_stderr(Discard)
  let stdout_result = try! @host.HostAsyncProcess::run_process_async(
    adapter, stdout_only,
  )
  assert_eq(stdout_result.stdout(), b"stdout")
  assert_eq(stdout_result.stderr(), b"")

  let stderr_only = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf stdout; printf stderr >&2",
  ])
  stderr_only.set_stdout(Discard)
  stderr_only.set_stderr(Capture)
  let stderr_result = try! @host.HostAsyncProcess::run_process_async(
    adapter, stderr_only,
  )
  assert_eq(stderr_result.stdout(), b"")
  assert_eq(stderr_result.stderr(), b"stderr")

  let failed = try! @host.CommandSpec::new("/bin/sh", ["-c", "exit 17"])
  failed.set_stdout(Capture)
  failed.set_stderr(Capture)
  let failed_result = try! @host.HostAsyncProcess::run_process_async(
    adapter, failed,
  )
  assert_eq(failed_result.termination(), Exited(17))
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native process helper coverage drains inherited output and stdin" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let inherited = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf out >/dev/null; printf err >/dev/null",
  ])
  inherited.set_stdout(@host.Inherit)
  inherited.set_stderr(@host.Inherit)
  inherited.set_inherit_stdin(false)
  inherited.set_stdin(b"input")
  let inherited_result = try! run_process_with_output_limit(inherited, 1024)
  assert_eq(inherited_result.termination(), Exited(0))

  let mixed = try! @host.CommandSpec::new("/bin/sh", [
    "-c", "printf out >/dev/null; printf err >/dev/null",
  ])
  mixed.set_stdout(@host.Inherit)
  mixed.set_stderr(@host.Capture)
  mixed.set_inherit_stdin(false)
  mixed.set_stdin(b"input")
  let mixed_result = try! run_process_with_output_limit(mixed, 1024)
  assert_eq(mixed_result.termination(), Exited(0))
  assert_eq(mixed_result.stderr(), b"")
  assert_eq(
    grouped_environment({ "A": "1" })["MOONJUST_INTERNAL_PROCESS_GROUP"],
    "1",
  )
  let executable = current_executable_for_group()
  assert_true(executable.length() > 0)
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native process helper forwards inherited streams and validates groups" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let output = ProcessAdapter::new()
  assert_eq(@host.HostAsyncOutput::write_output(output, Stdout, b""), 0)
  assert_eq(@host.HostAsyncOutput::write_output(output, Stderr, b""), 0)
  let stdout = try! @host.CommandSpec::new("/bin/sh", ["-c", ":"])
  stdout.set_stdout(Inherit)
  stdout.set_stderr(Discard)
  let stdout_result = try! run_process_with_output_limit(stdout, 64)
  assert_eq(stdout_result.termination(), Exited(0))
  let stderr = try! @host.CommandSpec::new("/bin/sh", ["-c", ":"])
  stderr.set_stdout(Discard)
  stderr.set_stderr(Inherit)
  let stderr_result = try! run_process_with_output_limit(stderr, 64)
  assert_eq(stderr_result.termination(), Exited(0))
  assert_eq(process_group_id(999999), 0)
  assert_eq(signal_process_group(-1, 0), 22)
  assert_false(process_group_alive(-1))
  try! cleanup_process_group(-1)
  try! cleanup_process_group_protected(-1)
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "group executable resolution and launch assembly are deterministic" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let directory = "moonjust-coverage-bin"
  try! @async_fs.mkdir(directory, permission=0o700)
  defer remove_windows_command_script(directory)
  let executable = directory + "/moonjust-tool"
  try! @async_fs.write_file(executable, b"", permission=0o700)
  defer remove_windows_command_script(executable)
  assert_eq(
    resolve_group_executable("/absolute/just", "", "/workspace"),
    "/absolute/just",
  )
  assert_eq(
    resolve_group_executable("bin/just", "", "/workspace"),
    "/workspace/bin/just",
  )
  assert_eq(
    resolve_group_executable("moonjust-tool", directory, "/workspace"),
    executable,
  )
  assert_eq(
    resolve_group_executable("missing", directory, "/workspace"),
    "missing",
  )
  assert_eq(resolve_group_executable("missing", "", "/workspace"), "missing")
  assert_eq(resolve_group_executable(directory, "", "."), directory)
  @async.with_task_group() <| group => {
    assert_eq(configure_signal_forwarding(group, true), None)
    guard signal_runtime.val is Some(state) else {
      abort("signal runtime was not initialized")
    }
    state.write.close()
    @async.sleep(0)
    state.read.close()
    signal_runtime.val = None
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native process helper maps write and setup failures" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let output = ProcessAdapter::new()
  assert_eq(@host.HostAsyncOutput::write_output(output, Stderr, b"."), 1)
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native signal runtime covers registration, diagnostics, and cleanup" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  @async.with_task_group() <| group => {
    assert_eq(configure_signal_forwarding(group, false), None)
    guard signal_runtime.val is Some(state) else {
      abort("signal runtime was not initialized")
    }
    assert_eq(caught_signal(), None)
    handle_signal(state, 29)
    assert_eq(caught_signal(), None)
    add_signal_child(999998, "first-coverage-child")
    add_signal_child(999999, "coverage-child")
    handle_signal(state, 29)
    handle_signal(state, 15)
    handle_signal(state, 2)
    assert_eq(caught_signal(), Some(15))
    assert_eq(signal_process_status(7), -271)
    state.first_signal = Some(1)
    cancel_signal_child(999999)
    state.first_signal = Some(15)
    remove_signal_child(123456)
    remove_signal_child(999998)
    remove_signal_child(999999)
    assert_eq(caught_signal(), None)
    signal_runtime.val = None
    add_signal_child(1, "ignored")
    remove_signal_child(1)
    assert_eq(signal_process_status(7), 7)
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async test "native signal pipe filters informational bytes and returns requests" {
  try! process_coverage_mutex.acquire()
  defer process_coverage_mutex.release()
  let (read, write) = try! @pipe.pipe()
  let state = SignalRuntime::{ read, write, children: [], first_signal: None }
  signal_runtime.val = Some(state)
  defer {
    state.read.close()
    state.write.close()
    signal_runtime.val = None
  }
  state.write.write(b"\x1d\x02")
  assert_eq(wait_for_signal_request(), Some("SIGINT"))

  let (observed_read, observed_write) = try! @pipe.pipe()
  let observed = SignalRuntime::{
    read: observed_read,
    write: observed_write,
    children: [],
    first_signal: None,
  }
  signal_runtime.val = Some(observed)
  @async.with_task_group() <| group => {
    let task = group.spawn(() => observe_signals())
    observed.write.write(b"\x02")
    observed.write.close()
    task.wait()
  }
  assert_eq(observed.first_signal, Some(2))
  observed.read.close()
  signal_runtime.val = None
}
