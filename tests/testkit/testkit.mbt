///|
pub(all) struct RunResult {
  status : Int
  stdout : Bytes
  stderr : Bytes
}

///|
pub(all) struct LiveRunResult {
  status : Int
  stdout : Bytes
  stderr : Bytes
  observed : Bool
}

///|
/// A command resolved once and then reused across repeated observations.
pub(all) struct PreparedProgram {
  executable : String
  prefix : Array[String]
}

///|
async fn resolve_program(program : String) -> String {
  if program.contains("/") || program.contains("\\") {
    @fs.realpath(program)
  } else {
    program
  }
}

///|
pub async fn prepare_program(
  program : String,
  runner? : String = "",
) -> PreparedProgram {
  let path = resolve_program(program)
  let executable = if runner.is_empty() {
    path
  } else {
    resolve_program(runner)
  }
  if runner.is_empty() {
    { executable, prefix: [], }
  } else if runner.contains("moonrun") {
    { executable, prefix: [path, "--"], }
  } else {
    { executable, prefix: [path], }
  }
}

///|
pub fn PreparedProgram::arguments(
  self : PreparedProgram,
  args : ArrayView[String],
) -> Array[String] {
  let result = self.prefix.copy()
  for argument in args {
    result.push(argument)
  }
  result
}

///|
async fn collect(
  program : String,
  args : Array[String],
  stdin_path : String?,
  cwd : String?,
  extra_env : Map[String, String],
  inherit_env : Bool,
) -> RunResult {
  let input = match stdin_path {
    Some(path) => Some(@process.redirect_from_file(path))
    None => None
  }
  let output = match (input, cwd) {
    (Some(source), Some(directory)) =>
      @process.collect_output(
        program,
        args,
        extra_env~,
        inherit_env~,
        stdin=source,
        cwd=directory,
        no_console_window=true,
      )
    (Some(source), None) =>
      @process.collect_output(
        program,
        args,
        extra_env~,
        inherit_env~,
        stdin=source,
        no_console_window=true,
      )
    (None, Some(directory)) =>
      @process.collect_output(
        program,
        args,
        extra_env~,
        inherit_env~,
        cwd=directory,
        no_console_window=true,
      )
    (None, None) =>
      @process.collect_output(
        program,
        args,
        extra_env~,
        inherit_env~,
        no_console_window=true,
      )
  }
  { status: output.0, stdout: output.1.binary(), stderr: output.2.binary(), }
}

///|
pub async fn run_prepared(
  program : PreparedProgram,
  args : Array[String],
  stdin_path? : String,
  cwd? : String,
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
) -> RunResult {
  collect(
    program.executable,
    program.arguments(args),
    stdin_path,
    cwd,
    extra_env,
    inherit_env,
  )
}

///|
pub async fn run(
  program : String,
  args : Array[String],
  stdin? : Bytes,
  cwd? : String,
  extra_env? : Map[String, String] = Map([]),
  inherit_env? : Bool = true,
) -> RunResult {
  let prepared = prepare_program(program)
  let input_dir = match stdin {
    Some(_) => Some(@fs.tmpdir(prefix="moonjust-input"))
    None => None
  }
  defer (if input_dir is Some(path) {
    @fs.rmdir(path, recursive=true) catch {
      _ => ()
    }
  })
  let input = match (input_dir, stdin) {
    (Some(dir), Some(data)) => {
      let path = @path.Path(dir).join(Path("stdin.bin")).to_string()
      @fs.write_file(path, data)
      Some(path)
    }
    _ => None
  }
  collect(
    prepared.executable,
    prepared.arguments(args),
    input,
    cwd,
    extra_env,
    inherit_env,
  )
}

///|
pub async fn run_merged(
  program : String,
  args : Array[String],
  stdin : Bytes,
  cwd : String,
  extra_env : Map[String, String],
  inherit_env? : Bool = false,
) -> (Int, Bytes) {
  let program = resolve_program(program)
  let input_dir = @fs.tmpdir(prefix="moonjust-input")
  defer (@fs.rmdir(input_dir, recursive=true) catch { _ => () })
  let input_path = @path.Path(input_dir).join(Path("stdin.bin")).to_string()
  @fs.write_file(input_path, stdin)
  let input = @process.redirect_from_file(input_path)
  let output = @process.collect_output_merged(
    program,
    args,
    extra_env~,
    inherit_env~,
    stdin=input,
    cwd~,
    no_console_window=true,
  )
  (output.0, output.1.binary())
}

///|
fn array_contains_bytes(haystack : Array[Byte], needle : BytesView) -> Bool {
  if needle.is_empty() {
    return true
  }
  if needle.length() > haystack.length() {
    return false
  }
  for start = 0; start <= haystack.length() - needle.length(); start = start + 1 {
    let mut matches = true
    for offset in 0..<needle.length() {
      if haystack[start + offset] != needle[offset] {
        matches = false
        break
      }
    }
    if matches {
      return true
    }
  }
  false
}

///|
pub async fn run_live_stdout(
  program : String,
  args : Array[String],
  stdin : Bytes,
  cwd : String,
  extra_env : Map[String, String],
  prefix : Bytes,
  timeout_ms : Int,
  inherit_env? : Bool = false,
) -> LiveRunResult {
  let program = resolve_program(program)
  let input_dir = @fs.tmpdir(prefix="moonjust-input")
  defer (@fs.rmdir(input_dir, recursive=true) catch { _ => () })
  let input_path = @path.Path(input_dir).join(Path("stdin.bin")).to_string()
  @fs.write_file(input_path, stdin)
  let input = @process.redirect_from_file(input_path)
  let (stdout_reader, stdout_writer) = @process.read_from_process()
  let (stderr_reader, stderr_writer) = @process.read_from_process()
  @async.with_task_group() <| group => {
    let started = @async.now()
    let child = @process.spawn(
      group,
      program,
      args,
      extra_env~,
      inherit_env~,
      stdin=input,
      stdout=stdout_writer,
      stderr=stderr_writer,
      cwd~,
      no_console_window=true,
    )
    let stdout_task = group.spawn(() => {
      defer stdout_reader.close()
      let output : Array[Byte] = []
      let mut observed = false
      while stdout_reader.read_some(max_len=64 * 1024) is Some(chunk) {
        for byte in chunk {
          output.push(byte)
        }
        if !observed &&
          @async.now() - started <= timeout_ms.to_int64() &&
          array_contains_bytes(output, prefix[:]) {
          observed = true
        }
      }
      (Bytes::from_array(output), observed)
    })
    let stderr_task = group.spawn(() => {
      defer stderr_reader.close()
      stderr_reader.read_all().binary()
    })
    let stdout_result = stdout_task.wait()
    {
      status: child.wait(),
      stdout: stdout_result.0,
      stderr: stderr_task.wait(),
      observed: stdout_result.1,
    }
  }
}

///|
pub fn bytes_equal(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index, byte in left {
    if byte != right[index] {
      return false
    }
  }
  true
}

///|
pub fn replace_bytes(
  input : Bytes,
  needle : BytesView,
  replacement : BytesView,
) -> Bytes {
  if needle.is_empty() || needle.length() > input.length() {
    return input
  }
  let output : Array[Byte] = []
  let mut index = 0
  while index < input.length() {
    let mut matches = index + needle.length() <= input.length()
    if matches {
      for offset in 0..<needle.length() {
        if input[index + offset] != needle[offset] {
          matches = false
          break
        }
      }
    }
    if matches {
      for byte in replacement {
        output.push(byte)
      }
      index += needle.length()
    } else {
      output.push(input[index])
      index += 1
    }
  }
  Bytes::from_array(output)
}
