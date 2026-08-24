///|
priv struct EvaluatedLine {
  command : String
  quiet : Bool
  ignore_error : Bool
  is_guard : Bool
}

///|
fn source_line_sigils(
  line : @syntax.RecipeLine,
  guards : Bool,
) -> (Int, Bool, Bool, Bool) {
  guard line.fragments().get(0) is Some(Text(text~, ..)) else {
    return (0, false, false, false)
  }
  let mut offset = 0
  let mut quiet = false
  let mut ignore_error = false
  while offset < text.length() {
    match text.unsafe_get(offset) {
      '@' => {
        quiet = true
        offset += 1
      }
      '-' => {
        ignore_error = true
        offset += 1
      }
      _ => break
    }
  }
  let is_guard = guards &&
    offset < text.length() &&
    text.unsafe_get(offset) == '?'
  if is_guard {
    offset += 1
  }
  (offset, quiet, ignore_error, is_guard)
}

///|
fn cooked_recipe_text(text : String) -> String {
  text.replace(old="{{{{", new="{{")
}

///|
fn evaluate_line(
  line : @syntax.RecipeLine,
  environment : @evaluator.Environment,
) -> EvaluatedLine raise ExecutionError {
  let rendered = render_line(line, environment)
  let (offset, quiet, ignore_error, _) = source_line_sigils(line, false)
  {
    command: rendered.view(start_offset=offset).to_owned(),
    quiet,
    ignore_error,
    is_guard: false,
  }
}

///|
fn render_line(
  line : @syntax.RecipeLine,
  environment : @evaluator.Environment,
) -> String raise ExecutionError {
  let output = StringBuilder()
  for fragment in line.fragments() {
    match fragment {
      Text(text~, ..) => output.write_string(cooked_recipe_text(text))
      Interpolation(expression~, ..) => {
        let value = @evaluator.evaluate(expression, environment~) catch {
          error => raise Evaluation(error)
        }
        output.write_string(value.to_string())
      }
    }
  }
  output.to_string()
}

///|
fn render_dry_expression(
  expression : @syntax.Expression,
  environment : @evaluator.Environment,
) -> String raise ExecutionError {
  match expression {
    Backtick(literal) => "`" + literal.cooked() + "`"
    Call(name~, arguments~, ..) if @builtin.is_effectful(name) => {
      let rendered : Array[String] = []
      for argument in arguments {
        let value = @evaluator.evaluate(argument, environment~) catch {
          error => raise Evaluation(error)
        }
        rendered.push(value.display())
      }
      name + "(" + rendered.join(", ") + ")"
    }
    _ => {
      let value = @evaluator.evaluate(expression, environment~) catch {
        error => raise Evaluation(error)
      }
      value.to_string()
    }
  }
}

///|
fn render_dry_line(
  line : @syntax.RecipeLine,
  environment : @evaluator.Environment,
) -> String raise ExecutionError {
  let output = StringBuilder()
  for fragment in line.fragments() {
    match fragment {
      Text(text~, ..) => output.write_string(cooked_recipe_text(text))
      Interpolation(expression~, ..) =>
        output.write_string(render_dry_expression(expression, environment))
    }
  }
  output.to_string()
}

///|
fn[
  T : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostProcess + @host.HostPlatform + @host.HostTerminal,
] render_effectful_line(
  host : T,
  line : @syntax.RecipeLine,
  environment : @evaluator.Environment,
  cwd : @path.PathValue,
  shell : @environment.ShellConfiguration,
  quiet : Bool,
) -> String raise ExecutionError {
  let effect_shell = @evaluator.EffectShell::new(
    shell.program(),
    shell.arguments().to_owned(),
  )
  let context = @evaluator.EvaluationContext::new(cwd~)
  let output = StringBuilder()
  for fragment in line.fragments() {
    match fragment {
      Text(text~, ..) => output.write_string(cooked_recipe_text(text))
      Interpolation(expression~, ..) => {
        let value = @evaluator.evaluate_with_effects(
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
  output.to_string()
}

///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] evaluate_async_line(
  process : P,
  host : H,
  line : @syntax.RecipeLine,
  environment : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
  quiet : Bool,
  dry_run : Bool,
  guards : Bool,
) -> EvaluatedLine raise ExecutionError {
  let effect_shell = @evaluator.EffectShell::new(
    shell.program(),
    shell.arguments().to_owned(),
  )
  let rendered = if dry_run {
    render_dry_line(line, environment)
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
    output.to_string()
  }
  let (offset, line_quiet, ignore_error, is_guard) = source_line_sigils(
    line, guards,
  )
  {
    command: rendered.view(start_offset=offset).to_owned(),
    quiet: line_quiet,
    ignore_error,
    is_guard,
  }
}

///|
/// Evaluate and construct an ordinary command at its exact execution point.
pub async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] materialize_line_async(
  process : P,
  host : H,
  planned : PlannedLine,
) -> (PlannedCommand, Bytes) raise ExecutionError {
  let line = evaluate_async_line(
    process,
    host,
    planned.source,
    planned.environment,
    planned.context,
    planned.shell,
    planned.options.quiet(),
    planned.options.dry_run(),
    planned.options.guards(),
  )
  let should_echo = planned.options.dry_run() ||
    planned.options.verbose() ||
    planned.options.timestamp() is Some(_) ||
    (
      !planned.options.quiet() &&
      !planned.options.echo_quiet() &&
      planned.recipe_quiet == line.quiet
    )
  let echo = if should_echo && !line.command.is_empty() {
    render_command_echo(
      line.command,
      timestamp=planned.options.timestamp(),
      color=planned.options.command_color(),
    )
  } else {
    b""
  }
  let spec = command_spec(
    planned.shell,
    line.command,
    planned.cwd,
    planned.process_environment,
    planned.options.quiet(),
    positional=planned.positional,
  )
  (
    PlannedCommand::new(
      spec,
      planned.recipe,
      planned.line,
      line.ignore_error,
      echo~,
      is_guard=line.is_guard,
      continue_signals=planned.continue_signals(),
    ),
    echo,
  )
}

///|
fn command_spec(
  shell : @environment.ShellConfiguration,
  command : String,
  cwd : @path.PathValue,
  environment : ArrayView[(String, String)],
  discard_output : Bool,
  positional? : ArrayView[String] = [],
) -> @host.CommandSpec raise ExecutionError {
  let arguments = shell.arguments().to_owned()
  arguments.push(command)
  if !positional.is_empty() {
    for argument in positional {
      arguments.push(argument)
    }
  }
  let spec = @host.CommandSpec::new(shell.program(), arguments) catch {
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
fn append_bytes(output : Array[Byte], bytes : BytesView) -> Unit {
  for byte in bytes {
    output.push(byte)
  }
}
