///|
priv struct ShebangCommand {
  interpreter : String
  argument : String?
}

///|
fn parse_shebang(line : String) -> ShebangCommand? {
  guard line.has_prefix("#!") else { return None }
  let text = line.view(start_offset=2).to_owned().trim().to_owned()
  if text.is_empty() {
    return None
  }
  let mut separator : Int? = None
  for index in 0..<text.length() {
    let byte = text.unsafe_get(index)
    if byte == ' ' || byte == '\t' {
      separator = Some(index)
      break
    }
  }
  match separator {
    None => Some({ interpreter: text, argument: None })
    Some(index) => {
      let interpreter = text[:index].to_owned()
      let argument = text.view(start_offset=index).to_owned().trim().to_owned()
      Some({
        interpreter,
        argument: if argument.is_empty() {
          None
        } else {
          Some(argument)
        },
      })
    }
  }
}

///|
fn executable_name(program : String) -> String {
  let normalized = program.replace(old="\\", new="/")
  normalized.split("/").last().unwrap_or(normalized[:]).to_owned()
}

///|
fn inferred_extension(program : String) -> String {
  match executable_name(program) {
    "cmd" | "cmd.exe" => ".bat"
    "powershell" | "powershell.exe" | "pwsh" | "pwsh.exe" => ".ps1"
    _ => ""
  }
}

///|
fn recipe_has_explicit_script_interpreter(recipe : @syntax.Recipe) -> Bool {
  recipe
  .attributes()
  .any(fn(attribute) {
    attribute.name() == "script" && !attribute.arguments().is_empty()
  })
}

///|
fn needs_bom(program : String) -> Bool {
  inferred_extension(program) == ".ps1"
}

///|
fn evaluated_script(
  recipe : @syntax.Recipe,
  environment : @evaluator.Environment,
) -> Array[String] raise ExecutionError {
  let result : Array[String] = []
  for line in recipe.lines() {
    result.push(render_line(line, environment))
  }
  result
}

///|
fn positioned_script_lines(
  recipe : @syntax.Recipe,
  lines : ArrayView[String],
  direct_shebang : Bool,
) -> Array[String] {
  if recipe.lines().is_empty() {
    return lines.to_owned()
  }
  let result : Array[String] = []
  let mut output_line = 1
  let mut shebang_prefix = direct_shebang
  for index, line in lines {
    let source = recipe.lines()[index]
    let normalize_shebang_line = shebang_prefix && line.has_prefix("#!")
    if !normalize_shebang_line {
      shebang_prefix = false
    }
    let start = if normalize_shebang_line {
      index + 1
    } else {
      source.source_start_line()
    }
    let end = if normalize_shebang_line {
      index + 1
    } else {
      source.source_end_line()
    }
    while output_line < start {
      result.push("")
      output_line += 1
    }
    result.push(line)
    output_line += 1
    while output_line <= end {
      result.push("")
      output_line += 1
    }
  }
  while result.last() is Some("") {
    ignore(result.pop())
  }
  result
}

///|
fn script_bytes(
  recipe : @syntax.Recipe,
  lines : ArrayView[String],
  bom : Bool,
  direct_shebang : Bool,
  strip_shebang : Bool,
) -> Bytes {
  let output : Array[Byte] = []
  if bom {
    append_bytes(output, @utf8.encode("\u{feff}")[:])
  }
  for line in positioned_script_lines(recipe, lines, direct_shebang) {
    let rendered = if strip_shebang && line.has_prefix("#!") {
      ""
    } else {
      line
    }
    append_bytes(output, @utf8.encode(rendered)[:])
    output.push(b'\n')
  }
  Bytes::from_array(output)
}

///|
/// Windows shebang lines are metadata for the generated script file, but they
/// remain part of the command text shown by dry-run and command echo output.
fn execution_script_contents(
  contents : Bytes,
  has_shebang : Bool,
  platform : @host.PlatformInfo,
) -> Bytes {
  guard platform.operating_system() == Windows && has_shebang else {
    return contents
  }
  let bytes = contents[:]
  let mut line_start = 0
  if bytes.length() >= 3 &&
    bytes[0] == b'\xef' &&
    bytes[1] == b'\xbb' &&
    bytes[2] == b'\xbf' {
    line_start = 3
  }
  let mut newline : Int? = None
  for index in line_start..<bytes.length() {
    if bytes[index] == b'\n' {
      newline = Some(index)
      break
    }
  }
  let output : Array[Byte] = []
  for index in 0..<line_start {
    output.push(bytes[index])
  }
  match newline {
    Some(index) => {
      output.push(b'\n')
      for rest in (index + 1)..<bytes.length() {
        output.push(bytes[rest])
      }
    }
    None => output.push(b'\n')
  }
  Bytes::from_array(output)
}

///|
fn prepare_planned_script(
  recipe : @syntax.Recipe,
  lines : Array[String],
  cwd : @path.PathValue,
  configuration : ScriptConfiguration,
  process_environment : ArrayView[(String, String)],
  positional : ArrayView[String],
  quiet : Bool,
  continue_signals? : ArrayView[@host.SignalKind] = [],
) -> PlannedScript raise ExecutionError {
  let shebang = match lines.get(0) {
    Some(line) if line.has_prefix("#!") &&
      !recipe_has_explicit_script_interpreter(recipe) =>
      match parse_shebang(line) {
        Some(_) => Some(line)
        None => raise InvalidShebang(recipe=recipe.name(), shebang=line)
      }
    _ => None
  }
  let program = match shebang {
    Some(line) => parse_shebang(line).unwrap().interpreter
    None => configuration.interpreter().program()
  }
  PlannedScript::new(
    recipe.name(),
    script_bytes(recipe, lines, needs_bom(program), shebang is Some(_), false),
    shebang,
    cwd,
    process_environment.to_owned(),
    configuration,
    positional,
    quiet,
    continue_signals~,
  )
}

///|
pub fn plan_script_recipe(
  recipe : @syntax.Recipe,
  environment : @evaluator.Environment,
  cwd : @path.PathValue,
  configuration : ScriptConfiguration,
  process_environment? : ArrayView[(String, String)] = [],
  positional? : ArrayView[String] = [],
  quiet? : Bool = false,
  continue_signals? : ArrayView[@host.SignalKind] = [],
) -> PlannedScript raise ExecutionError {
  prepare_planned_script(
    recipe,
    evaluated_script(recipe, environment),
    cwd,
    configuration,
    process_environment,
    positional,
    quiet,
    continue_signals~,
  )
}

///|
pub async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_script_recipe_async(
  process : P,
  host : H,
  recipe : @syntax.Recipe,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  cwd : @path.PathValue,
  configuration : ScriptConfiguration,
  process_environment? : ArrayView[(String, String)] = [],
  positional? : ArrayView[String] = [],
  quiet? : Bool = false,
  dry_run? : Bool = false,
  continue_signals? : ArrayView[@host.SignalKind] = [],
) -> PlannedScript raise ExecutionError {
  let effect_shell = @evaluator.EffectShell::new(
    shell.program(),
    shell.arguments().to_owned(),
  )
  let lines : Array[String] = []
  for line in recipe.lines() {
    if dry_run {
      lines.push(render_dry_line(line, environment))
    } else {
      let output = StringBuilder()
      for fragment in line.fragments() {
        match fragment {
          Text(text~, ..) => output.write_string(cooked_recipe_text(text))
          Interpolation(expression~, ..) => {
            let value = @evaluator.evaluate_with_async_effects(
              process,
              host,
              expression,
              context,
              effect_shell,
              quiet~,
              environment~,
            ) catch {
              error => raise Evaluation(error)
            }
            output.write_string(value.to_string())
          }
        }
      }
      lines.push(output.to_string())
    }
  }
  prepare_planned_script(
    recipe,
    lines,
    cwd,
    configuration,
    process_environment,
    positional,
    quiet,
    continue_signals~,
  )
}

///|
/// Create the runtime temporary and exact script process request.
pub fn[T : @host.HostScriptTemp + @host.HostExecutable] materialize_script(
  host : T,
  planned : PlannedScript,
) -> MaterializedScript raise ExecutionError {
  let configuration = planned.configuration
  let parsed = planned.shebang.map(fn(line) { parse_shebang(line).unwrap() })
  let program = match parsed {
    Some(value) => value.interpreter
    None => configuration.interpreter().program()
  }
  let extension = configuration
    .extension()
    .unwrap_or(inferred_extension(program))
  let path = @host.HostScriptTemp::create_script_temp(
    host,
    configuration.temporary_directory(),
    planned.recipe,
    extension,
    execution_script_contents(
      planned.contents,
      planned.shebang is Some(_),
      configuration.platform(),
    ),
  ) catch {
    error => raise Host(error)
  }
  if parsed is Some(_) {
    try @host.HostExecutable::set_executable(host, path) catch {
      error => {
        try @host.HostScriptTemp::remove_script_temp(host, path) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        raise Host(error)
      }
    } noraise {
      _ => ()
    }
  }
  let spec = script_command(
    path,
    planned.cwd,
    planned.environment,
    configuration.interpreter(),
    parsed,
    configuration.platform(),
    planned.quiet,
    positional=planned.positional,
  ) catch {
    error => {
      try @host.HostScriptTemp::remove_script_temp(host, path) catch {
        _ => ()
      } noraise {
        _ => ()
      }
      raise error
    }
  }
  MaterializedScript::new(path, spec)
}

///|
pub fn[T : @host.HostScriptTemp] cleanup_materialized_script(
  host : T,
  script : MaterializedScript,
) -> Unit raise ExecutionError {
  cleanup_script(host, script.path())
}

///|
pub async fn[T : @host.HostAsyncScriptTemp] materialize_script_async(
  host : T,
  planned : PlannedScript,
) -> MaterializedScript raise ExecutionError {
  let configuration = planned.configuration
  let parsed = planned.shebang.map(fn(line) { parse_shebang(line).unwrap() })
  let program = match parsed {
    Some(value) => value.interpreter
    None => configuration.interpreter().program()
  }
  let extension = configuration
    .extension()
    .unwrap_or(inferred_extension(program))
  let path = @host.HostAsyncScriptTemp::create_script_temp_async(
    host,
    configuration.temporary_directory(),
    planned.recipe,
    extension,
    execution_script_contents(
      planned.contents,
      planned.shebang is Some(_),
      configuration.platform(),
    ),
    parsed is Some(_),
  ) catch {
    error => raise Host(error)
  }
  let spec = script_command(
    path,
    planned.cwd,
    planned.environment,
    configuration.interpreter(),
    parsed,
    configuration.platform(),
    planned.quiet,
    positional=planned.positional,
  ) catch {
    error => {
      try
        @host.HostAsyncScriptTemp::remove_script_temp_async(host, path)
      catch {
        _ => ()
      } noraise {
        _ => ()
      }
      raise error
    }
  }
  MaterializedScript::new(path, spec)
}

///|
pub async fn[T : @host.HostAsyncScriptTemp] cleanup_materialized_script_async(
  host : T,
  script : MaterializedScript,
) -> Unit raise ExecutionError {
  @host.HostAsyncScriptTemp::remove_script_temp_async(host, script.path()) catch {
    error => raise Host(error)
  }
}

///|
fn script_command(
  path : @path.PathValue,
  cwd : @path.PathValue,
  environment : ArrayView[(String, String)],
  interpreter : @environment.ShellConfiguration,
  shebang : ShebangCommand?,
  platform : @host.PlatformInfo,
  discard_output : Bool,
  positional? : ArrayView[String] = [],
) -> @host.CommandSpec raise ExecutionError {
  let (program, arguments) = match shebang {
    Some(value) if platform.operating_system() == Windows => {
      let arguments : Array[String] = []
      match value.argument {
        Some(argument) => arguments.push(argument)
        None => ()
      }
      arguments.push(path.as_string())
      (value.interpreter, arguments)
    }
    Some(_) => (path.as_string(), [])
    None => {
      let arguments = interpreter.arguments().to_owned()
      arguments.push(path.as_string())
      (interpreter.program(), arguments)
    }
  }
  for argument in positional {
    arguments.push(argument)
  }
  let spec = @host.CommandSpec::new(program, arguments) catch {
    error => raise Host(error)
  }
  spec.set_cwd(cwd)
  spec.set_inherit_environment(false)
  for _, entry in environment {
    let (key, value) = entry
    spec.add_environment(key, value) catch {
      error => raise Host(error)
    }
  }
  spec.set_stdin(b"")
  spec.set_stdout(if discard_output { Discard } else { Capture })
  spec.set_stderr(if discard_output { Discard } else { Capture })
  spec
}

///|
fn[T : @host.HostScriptTemp] cleanup_script(
  host : T,
  path : @path.PathValue,
) -> Unit raise ExecutionError {
  @host.HostScriptTemp::remove_script_temp(host, path) catch {
    error => raise Host(error)
  }
}

///|
/// Evaluate and run a script recipe as one temporary program. Evaluation and
/// dry-run output happen before any file is created.
pub fn[T : @host.HostProcess + @host.HostScriptTemp + @host.HostExecutable] execute_script_recipe(
  host : T,
  recipe : @syntax.Recipe,
  environment : @evaluator.Environment,
  cwd : @path.PathValue,
  configuration : ScriptConfiguration,
  process_environment? : ArrayView[(String, String)] = [],
  options? : ExecutionOptions = ExecutionOptions::new(),
) -> ExecutionReport raise ExecutionError {
  let lines = evaluated_script(recipe, environment)
  let dry_stderr : Array[Byte] = []
  if options.dry_run() {
    for line in lines {
      append_bytes(dry_stderr, @utf8.encode(line)[:])
      dry_stderr.push(b'\n')
    }
    return ExecutionReport::new(b"", Bytes::from_array(dry_stderr), 0)
  }
  let shebang = match lines.get(0) {
    Some(line) if line.has_prefix("#!") &&
      !recipe_has_explicit_script_interpreter(recipe) =>
      match parse_shebang(line) {
        Some(value) => Some(value)
        None => raise InvalidShebang(recipe=recipe.name(), shebang=line)
      }
    _ => None
  }
  let program = match shebang {
    Some(value) => value.interpreter
    None => configuration.interpreter().program()
  }
  let extension = configuration
    .extension()
    .unwrap_or(inferred_extension(program))
  let contents = script_bytes(
    recipe,
    lines,
    needs_bom(program),
    shebang is Some(_),
    false,
  )
  let contents = execution_script_contents(
    contents,
    shebang is Some(_),
    configuration.platform(),
  )
  let path = @host.HostScriptTemp::create_script_temp(
    host,
    configuration.temporary_directory(),
    recipe.name(),
    extension,
    contents,
  ) catch {
    error => raise Host(error)
  }
  if shebang is Some(_) {
    try @host.HostExecutable::set_executable(host, path) catch {
      error => {
        try cleanup_script(host, path) catch {
          _ => ()
        } noraise {
          _ => ()
        }
        raise Host(error)
      }
    } noraise {
      _ => ()
    }
  }
  let spec = script_command(
    path,
    cwd,
    process_environment,
    configuration.interpreter(),
    shebang,
    configuration.platform(),
    options.quiet(),
  ) catch {
    error => {
      try cleanup_script(host, path) catch {
        _ => ()
      } noraise {
        _ => ()
      }
      raise error
    }
  }
  let result = try @host.HostProcess::run_process(host, spec) catch {
    error => {
      try cleanup_script(host, path) catch {
        _ => ()
      } noraise {
        _ => ()
      }
      raise Host(error)
    }
  } noraise {
    value => value
  }
  cleanup_script(host, path)
  match result.termination() {
    Exited(0) =>
      ExecutionReport::new(
        result.stdout().to_owned(),
        result.stderr().to_owned(),
        1,
      )
    Exited(exit_code) =>
      raise CommandFailed(recipe=recipe.name(), line=0, exit_code~)
    Signaled(signal) =>
      raise CommandSignaled(recipe=recipe.name(), line=0, signal~)
    Interrupted(signal) => raise Interrupted(signal~)
  }
}
