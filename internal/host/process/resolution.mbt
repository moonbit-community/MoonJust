///|
async fn materialize_windows_command(
  program : String,
  arguments : ArrayView[String],
  cwd : String,
  environment : ArrayView[(String, String)],
  inherit_environment : Bool,
) -> (String, Array[String], String?) raise @host.HostError {
  if !windows_process_runtime() {
    return (program, arguments.to_owned(), None)
  }
  let lower = program.to_lower()
  let is_batch = lower.has_suffix(".cmd") || lower.has_suffix(".bat")
  let basename = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or(program[:])
    .to_lower()
  let is_cmd = basename == "cmd.exe" || basename == "cmd"
  let mut body : String? = None
  let mut command_index : Int? = None
  if is_cmd {
    for index, argument in arguments {
      let lower_argument = argument.to_lower()
      if lower_argument == "/c" || lower_argument == "/command" {
        if index + 1 < arguments.length() {
          body = Some(arguments[index + 1])
          command_index = Some(index)
          break
        }
      }
    }
  } else if is_batch {
    body = Some(
      "@echo off\r\ncall \"" +
      program.replace_all(old="\"", new="\"\"") +
      "\" %*\r\nexit /b %errorlevel%\r\n",
    )
  }
  guard body is Some(command) else {
    return (program, arguments.to_owned(), None)
  }
  if is_cmd &&
    command_index is Some(index) &&
    index + 2 == arguments.length() &&
    windows_direct_command_safe(command) {
    return (program, arguments.to_owned(), None)
  }
  let command_lower = command.to_lower()
  let command_is_batch_path = (
      command_lower.has_suffix(".cmd") || command_lower.has_suffix(".bat")
    ) &&
    (try @async_fs.kind(command) catch {
      _ => false
    } noraise {
      Regular => true
      _ => false
    })
  let command_for_batch = windows_escape_undefined_variables(
    windows_batch_body(command),
    environment,
    inherit_environment,
  )
  let script = if is_batch {
    command
  } else if command_is_batch_path {
    "@echo off\r\ncall \"" +
    command.replace_all(old="\"", new="\"\"") +
    "\"\r\nexit /b %errorlevel%\r\n"
  } else {
    "@" + command_for_batch + "\r\n"
  }
  let filename = ".moonjust-cmd-" + process_random_suffix() + ".cmd"
  let path = if cwd == "." || cwd.is_empty() {
    filename
  } else if cwd.has_suffix("\\") || cwd.has_suffix("/") {
    cwd + filename
  } else {
    cwd + "\\" + filename
  }
  @async_fs.write_file(
    path,
    @utf8.encode(script),
    create_mode=CreateNew,
    permission=0o600,
  ) catch {
    _ => raise InvalidInput("failed to create temporary Windows command script")
  }
  let rewritten : Array[String] = []
  if is_batch {
    rewritten.push("/d")
    rewritten.push("/s")
    rewritten.push("/c")
    rewritten.push(path)
    for argument in arguments {
      rewritten.push(argument)
    }
  } else {
    let index = command_index.unwrap()
    rewritten.push("/d")
    rewritten.push("/s")
    for argument in arguments[:index] {
      let lower_argument = argument.to_lower()
      if lower_argument != "/d" && lower_argument != "/s" {
        rewritten.push(argument)
      }
    }
    rewritten.push("/c")
    rewritten.push(path)
    for argument in arguments[index + 2:] {
      rewritten.push(argument)
    }
  }
  ("cmd.exe", rewritten, Some(path))
}

///|
async fn remove_windows_command_script(path : String) -> Unit {
  try @async_fs.remove(path) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async fn windows_native_program(
  program : String,
  cwd : String,
) -> String noraise {
  if !windows_process_runtime() || !program.contains("/") {
    return program
  }
  let cygpath = @env.get_env_var("JUST_CYGPATH").unwrap_or("cygpath")
  let (status, stdout, _) = try
    @async_process.collect_output(cygpath, ["--windows", program], cwd~)
  catch {
    _ => return program
  } noraise {
    value => value
  }
  if status != 0 {
    return program
  }
  let translated = try stdout.text() catch {
    _ => return program
  } noraise {
    value => value.trim_end().to_owned()
  }
  if translated.is_empty() {
    program
  } else {
    translated
  }
}

///|
#cfg(platform="windows")
fn windows_process_runtime() -> Bool {
  true
}

///|
#cfg(not(platform="windows"))
fn windows_process_runtime() -> Bool {
  @env.get_env_var("MOONJUST_OS") == Some("windows")
}

///|
async fn resolve_process_program_with_context(
  program : String,
  cwd : String,
  path : String,
  pathext : String,
) -> String {
  if !windows_process_runtime() {
    return program
  }
  let program = windows_native_program(program, cwd)
  for candidate in windows_program_candidates(program, path, pathext) {
    let regular = try @async_fs.kind(candidate) catch {
      _ => false
    } noraise {
      Regular => true
      _ => false
    }
    if regular {
      return candidate
    }
  }
  program
}

///|
async fn resolve_process_program(program : String, cwd : String) -> String {
  resolve_process_program_with_context(
    program,
    cwd,
    @env.get_env_var("PATH").unwrap_or(""),
    @env.get_env_var("PATHEXT").unwrap_or(".COM;.EXE;.BAT;.CMD"),
  )
}

///|
fn windows_resolution_key(
  program : String,
  cwd : String,
  path : String,
  pathext : String,
  cygpath : String,
  shell_mode? : String = "auto",
) -> String {
  program +
  "\u{0000}" +
  cwd +
  "\u{0000}" +
  path +
  "\u{0000}" +
  pathext +
  "\u{0000}" +
  cygpath +
  "\u{0000}" +
  shell_mode
}

///|
fn windows_shell_mode(
  program : String,
  arguments : ArrayView[String],
) -> String {
  let basename = program
    .replace_all(old="\\", new="/")
    .split("/")
    .last()
    .unwrap_or(program[:])
    .to_lower()
  if basename == "cmd" || basename == "cmd.exe" {
    if arguments.contains("/c") || arguments.contains("/command") {
      "cmd-command"
    } else {
      "cmd"
    }
  } else if basename.has_suffix(".cmd") || basename.has_suffix(".bat") {
    "batch"
  } else {
    "direct"
  }
}

///|
async fn resolve_process_program_cached(
  program : String,
  cwd : String,
  arguments : ArrayView[String],
) -> String {
  if !windows_process_runtime() {
    return program
  }
  let path = @env.get_env_var("PATH").unwrap_or("")
  let pathext = @env.get_env_var("PATHEXT").unwrap_or(".COM;.EXE;.BAT;.CMD")
  let key = windows_resolution_key(
    program,
    cwd,
    path,
    pathext,
    @env.get_env_var("JUST_CYGPATH").unwrap_or("cygpath"),
    shell_mode=windows_shell_mode(program, arguments),
  )
  let acquired = try process_resolution_mutex.acquire() catch {
    _ => false
  } noraise {
    _ => true
  }
  if !acquired {
    return resolve_process_program(program, cwd)
  }
  defer process_resolution_mutex.release()
  match process_resolution_cache.get(key) {
    Some(value) => value
    None => {
      let resolved = resolve_process_program(program, cwd)
      if process_resolution_cache.length() >= 256 {
        process_resolution_cache.clear()
      }
      process_resolution_cache[key] = resolved
      resolved
    }
  }
}

///|
async fn read_bounded_process_output(
  output_mutex : @async.Mutex,
  reader : @async_process.ReadFromProcess,
  limit : Int,
  retain : Bool,
  process : ObservedProcess,
  forward : @host.OutputStream?,
) -> (Bytes, Bool) {
  defer reader.close()
  let output = Buffer(
    size_hint=if retain { Int::min(limit, 64 * 1024) } else { 0 },
  )
  while true {
    let max_length = if retain {
      Int::min(64 * 1024, Int::max(limit - output.length(), 0) + 1)
    } else {
      64 * 1024
    }
    guard reader.read_some(max_len=max_length) is Some(chunk) else { break }
    match forward {
      Some(stream) => {
        ignore(write_stdio(output_mutex, stream, chunk))
        continue
      }
      None => ()
    }
    if !retain {
      continue
    }
    let remaining = Int::max(limit - output.length(), 0)
    if chunk.length() > remaining {
      if remaining > 0 {
        output.write_bytes(chunk[:remaining])
      }
      process.cancel()
      return (output.to_bytes(), true)
    }
    output.write_bytes(chunk)
  }
  (output.to_bytes(), false)
}

///|
fn process_result(
  command : @host.CommandSpec,
  outcome : WaitOutcome,
  stdout : Bytes,
  stderr : Bytes,
) -> @host.ProcessResult {
  let captured_stdout = if command.stdout() == Capture { stdout } else { b"" }
  let captured_stderr = if command.stderr() == Capture { stderr } else { b"" }
  match outcome {
    Cancelled =>
      @host.ProcessResult::from_interruption(
        Interrupt,
        captured_stdout,
        captured_stderr,
      )
    Completed(status) if status < 0 =>
      @host.ProcessResult::from_signal(
        signal_from_status(status),
        captured_stdout,
        captured_stderr,
      )
    Completed(status) =>
      @host.ProcessResult::new(status, captured_stdout, captured_stderr)
  }
}

///|
