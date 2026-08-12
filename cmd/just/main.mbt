///|
fn[E : @host.HostEnv] parse_environment(
  environment_host : E,
) -> Map[String, String] raise @host.HostError {
  let environment : Map[String, String] = Map([])
  for entry in @host.HostEnv::env_entries(environment_host) {
    environment[entry.0] = entry.1
  }
  environment
}

///|
fn failure(message : String, exit_code : Int) -> @cli.ApplicationResponse {
  @cli.ApplicationResponse::new(
    b"",
    @utf8.encode(message.trim_end().to_owned() + "\n"),
    exit_code,
  )
}

///|
async fn confirm_execution(
  plan : @executor.ExecutionPlan,
) -> @cli.ApplicationResponse? {
  for request in plan.confirmations() {
    try @stdio.stderr.write(@utf8.encode(request.prompt() + " ")) catch {
      _ => return Some(failure("error: failed to write confirmation prompt", 1))
    } noraise {
      _ => ()
    }
    let answer = try @stdio.stdin.read_until("\n") catch {
      _ =>
        return Some(failure("error: failed to read confirmation from stdin", 1))
    } noraise {
      value => value
    }
    if answer is None ||
      !@executor.confirmation_answer_is_yes(answer.unwrap_or("")) {
      return Some(
        failure("error: recipe `" + request.recipe() + "` was not confirmed", 1),
      )
    }
  }
  None
}

///|
async fn[
  F : @host.HostFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  E : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
  P : @host.HostAsyncProcess,
] execute_run(
  host : F,
  environment_host : E,
  process : P,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
) -> @cli.ApplicationResponse {
  let plan = try
    @application.plan_run_command_async(
      host, environment_host, process, arguments, context,
    )
  catch {
    error => return failure(error.message(), error.exit_code())
  } noraise {
    value => value
  }
  if !arguments.flag("yes") {
    match confirm_execution(plan) {
      Some(response) => return response
      None => ()
    }
  }
  let report = try
    @runtime.execute_plan(process, host, environment_host, plan)
  catch {
    error => {
      let stderr : Array[Byte] = []
      for byte in error.stderr() {
        stderr.push(byte)
      }
      for byte in @utf8.encode(error.message().trim_end().to_owned() + "\n") {
        stderr.push(byte)
      }
      return @cli.ApplicationResponse::new(
        error.stdout().to_owned(),
        Bytes::from_array(stderr),
        error.exit_code(),
      )
    }
  } noraise {
    value => value
  }
  @cli.ApplicationResponse::new(
    report.stdout().to_owned(),
    report.stderr().to_owned(),
    0,
  )
}

///|
fn append_response(
  stdout : Array[Byte],
  stderr : Array[Byte],
  response : @cli.ApplicationResponse,
) -> Unit {
  for byte in response.stdout() {
    stdout.push(byte)
  }
  for byte in response.stderr() {
    stderr.push(byte)
  }
}

///|
async fn[
  F : @host.HostFs + @host.HostTemp + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  E : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] run_cli(
  host : F,
  environment_host : E,
  argv : ArrayView[String],
  stdin : Bytes,
) -> @cli.ApplicationResponse {
  let environment = try parse_environment(environment_host) catch {
    error =>
      return failure(
        "error: failed to read process environment: \{Repr(error)}",
        1,
      )
  } noraise {
    value => value
  }
  let arguments = try @cli.parse_arguments(argv, environment) catch {
    Invalid(message) => return failure(message, 2)
    Unsupported(name) =>
      return failure("error: option '\{name}' is not supported yet", 2)
  } noraise {
    value => value
  }
  if arguments.flag("help") {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(@cli.render_help()),
    )
  }
  if arguments.flag("version") {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(@moonjust.version_line() + "\n"),
    )
  }
  let cwd = try @host.HostEnv::current_dir(environment_host) catch {
    error =>
      return failure("error: invalid current directory: \{Repr(error)}", 1)
  } noraise {
    value => value
  }
  let context = @application.ApplicationContext::new(cwd, stdin~)
  let process = @host_process.ProcessAdapter::new()
  if arguments.command() == RunCommand {
    execute_run(host, environment_host, process, arguments, context)
  } else if arguments.command() == ChooseCommand {
    let selections = try
      @application.execute_choose_command_async(
        host, environment_host, process, arguments, context,
      )
    catch {
      error => return failure(error.message(), error.exit_code())
    } noraise {
      value => value
    }
    let stdout : Array[Byte] = []
    let stderr : Array[Byte] = []
    for selection in selections {
      let response = execute_run(
        host,
        environment_host,
        process,
        arguments.with_run_positionals(selection),
        context,
      )
      append_response(stdout, stderr, response)
      if response.exit_code() != 0 {
        return @cli.ApplicationResponse::new(
          Bytes::from_array(stdout),
          Bytes::from_array(stderr),
          response.exit_code(),
        )
      }
    }
    @cli.ApplicationResponse::new(
      Bytes::from_array(stdout),
      Bytes::from_array(stderr),
      0,
    )
  } else if arguments.command() == EditCommand {
    try
      @application.execute_edit_command_async(
        host, environment_host, process, arguments, context,
      )
    catch {
      error => failure(error.message(), error.exit_code())
    } noraise {
      response => response
    }
  } else if arguments.command() == CleanCommand {
    try @application.execute_clean_command(host, arguments, context) catch {
      error => failure(error.message(), error.exit_code())
    } noraise {
      response => response
    }
  } else {
    try
      @application.execute_command_with_terminal(
        host, environment_host, arguments, context,
      )
    catch {
      error => failure(error.message(), error.exit_code())
    } noraise {
      response => response
    }
  }
}

///|
async fn emit_response(response : @cli.ApplicationResponse) -> Unit {
  if !response.stdout().is_empty() {
    @stdio.stdout.write(response.stdout())
  }
  if !response.stderr().is_empty() {
    @stdio.stderr.write(response.stderr())
  }
  runtime_exit(response.exit_code())
}

///|
async fn main {
  let raw_argv = @env.args()
  let argv = raw_argv[1:]
  let environment_host = runtime_environment_host()
  let parsed = try {
    let environment = parse_environment(environment_host)
    Some(@cli.parse_arguments(argv, environment))
  } catch {
    _ => None
  }
  let stdin = if parsed is Some(arguments) &&
    !arguments.flag("help") &&
    !arguments.flag("version") &&
    arguments.value("justfile") == Some("-") {
    @stdio.stdin.read_all().binary() catch {
      _ => b""
    }
  } else {
    b""
  }
  emit_response(run_cli(runtime_host(), environment_host, argv, stdin)) catch {
    _ => runtime_exit(1)
  }
}
