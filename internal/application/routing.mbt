///|
pub struct InvocationEnvironment {
  entries : Array[(String, String)]
  values : Map[String, String]
}

///|
pub fn InvocationEnvironment::entries(
  self : InvocationEnvironment,
) -> ArrayView[(String, String)] {
  self.entries[:]
}

///|
pub fn InvocationEnvironment::values(
  self : InvocationEnvironment,
) -> Map[String, String] {
  self.values
}

///|
pub enum PreparedInvocation {
  Ready(@cli.CliArguments, InvocationEnvironment)
  Respond(@cli.ApplicationResponse)
}

///|
pub fn[E : @host.HostEnv] parse_environment(
  environment_host : E,
) -> InvocationEnvironment raise @host.HostError {
  let entries = @host.HostEnv::env_entries(environment_host)
  let values : Map[String, String] = Map([])
  for entry in entries {
    values[entry.0] = entry.1
  }
  { entries, values, }
}

///|
fn request_response(
  argv : ArrayView[String],
  environment : Map[String, String],
  windows : Bool,
) -> @cli.ApplicationResponse? {
  if argv.length() != 2 || argv[0] != "--request" {
    return None
  }
  let request = @json.parse(argv[1][:]) catch {
    _ => return Some(failure("error: invalid request", 2))
  }
  if request is String("signal") {
    return Some(
      failure("error: signal observation is unavailable in async-only mode", 2),
    )
  }
  guard request is Object(fields) &&
    fields.get("environment-variable") is Some(String(name)) else {
    return Some(failure("error: invalid request", 2))
  }
  let response = match environment.get(name) {
    None => "{\"environment-variable\":null}"
    Some(value) => {
      let numbers : Array[String] = []
      if windows {
        for character in value {
          let code = character.to_int()
          if code <= 0xffff {
            numbers.push(code.to_string())
          } else {
            let scalar = code - 0x10000
            numbers.push((0xd800 + (scalar >> 10)).to_string())
            numbers.push((0xdc00 + (scalar & 0x3ff)).to_string())
          }
        }
      } else {
        for byte in @utf8.encode(value) {
          numbers.push(byte.to_int().to_string())
        }
      }
      let platform = if windows { "Windows" } else { "Unix" }
      "{\"environment-variable\":{\"" +
      platform +
      "\":[" +
      numbers.join(",") +
      "]}}"
    }
  }
  Some(@cli.ApplicationResponse::success(stdout=@utf8.encode(response)))
}

///|
pub fn[E : @host.HostEnv + @host.HostPlatform] classify_request(
  environment_host : E,
  argv : ArrayView[String],
) -> PreparedInvocation {
  match static_invocation_response(argv) {
    Some(response) => return Respond(response)
    None => ()
  }
  let environment = try parse_environment(environment_host) catch {
    error =>
      return Respond(
        failure("error: failed to read process environment: \{Repr(error)}", 1),
      )
  } noraise {
    value => value
  }
  if argv.length() == 2 && argv[0] == "--request" {
    let windows = try
      @host.HostPlatform::platform_info(environment_host)
    catch {
      _ => false
    } noraise {
      value => value.operating_system() == Windows
    }
    match request_response(argv, environment.values, windows) {
      Some(response) => return Respond(response)
      None => ()
    }
  }
  let arguments = try @cli.parse_arguments(argv, environment.values) catch {
    Invalid(message) => return Respond(failure(message, 2))
    Config(message) => return Respond(failure(message, 1))
    Unsupported(name) =>
      return Respond(failure("error: option '\{name}' is not supported yet", 2))
  } noraise {
    value => value
  }
  Ready(arguments, environment)
}

///|
pub async fn read_stdin_source_bounded(max_bytes : Int32) -> Bytes {
  let read_limit = max_bytes + 1
  let result = Buffer(capacity=Int32::min(read_limit, 64 * 1024))
  let buffer = FixedArray::make(Int32::min(read_limit, 64 * 1024), b'\x00')
  while result.length() < read_limit {
    let count = @stdio.stdin.read_into(
      buffer,
      max_len=Int32::min(buffer.length(), read_limit - result.length()),
    )
    if count == 0 {
      break
    }
    result.write_bytes(buffer.unsafe_reinterpret_as_bytes()[:count])
  }
  result.to_bytes()
}

///|
async fn confirm_recipe(
  recipe : String,
  prompt : String,
) -> Unit raise @planner.ExecutionError {
  @stdio.stderr.write(@utf8.encode(prompt + " ")) catch {
    _ =>
      raise ConfirmationFailure(message="failed to write confirmation prompt")
  }
  let answer = @stdio.stdin.text.read_until("\n") catch {
    _ =>
      raise ConfirmationFailure(
        message="failed to read confirmation from stdin",
      )
  }
  if !@planner.confirmation_answer_is_yes(answer.unwrap_or("")) {
    raise ConfirmationFailure(
      message="recipe `" + recipe + "` was not confirmed",
    )
  }
}

///|
fn application_failure(
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  error : ApplicationError,
) -> @cli.ApplicationResponse {
  let message = render_application_error(arguments, context, error)
  let message = color_error_message(arguments, message)
  let response = failure(message, error.exit_code())
  if arguments.flag("quiet") {
    @cli.ApplicationResponse::new(
      response.stdout().to_owned(),
      b"",
      response.exit_code(),
    )
  } else {
    response
  }
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
  F : @host.HostFs + @host.HostScriptTemp + @host.HostCacheStore,
  E : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
  P : @host.HostProcess + @host.HostAsyncOutput,
] execute_run(
  loading_host : F,
  execution_host : F,
  environment_host : E,
  process : P,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  default_list~ : Bool = false,
) -> @cli.ApplicationResponse {
  let prepared = try
    prepare_run(
      loading_host,
      environment_host,
      process,
      arguments,
      context,
      default_list~,
    )
  catch {
    error => return application_failure(arguments, context, error)
  } noraise {
    value => value
  }
  let (plan, graph, cwd) = match prepared {
    Listing(response) => return response
    Ready(plan, graph, cwd) => (plan, graph, cwd)
  }
  try
    @runtime.execute_plan_live(
      process, process, execution_host, environment_host, plan, confirm_recipe,
    )
  catch {
    error =>
      return if (
          arguments.flag("quiet") && !(error.error() is ConfirmationFailure(_))
        ) ||
        !error.show_message() {
        @cli.ApplicationResponse::new(b"", b"", error.exit_code())
      } else {
        let message = match error.error() {
          Evaluation(value) =>
            render_application_error(
              arguments,
              context,
              ApplicationError::Evaluation(value).with_project_sources(
                graph, cwd,
              ),
            )
          _ => error.message()
        }
        failure(color_error_message(arguments, message), error.exit_code())
      }
  } noraise {
    _ => @cli.ApplicationResponse::success()
  }
}

///|
#warnings("-unused_trait_bound")
pub async fn[
  F : @host.HostFs + @host.HostAtomicFs + @host.HostScriptTemp + @host.HostCacheStore,
  E : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] run_prepared_cli(
  loading_host : F,
  execution_host : F,
  environment_host : E,
  arguments : @cli.CliArguments,
  environment : InvocationEnvironment,
  stdin : Bytes,
) -> @cli.ApplicationResponse {
  if arguments.flag("help") {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(@cli.render_help()),
    )
  }
  if arguments.flag("version") {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(version_line() + "\n"),
    )
  }
  if arguments.command() == ChangelogCommand {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(just_changelog),
    )
  }
  if arguments.command() == ManCommand {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(JUST_MAN_PAGE + "\n"),
    )
  }
  let context = try @host.HostEnv::current_dir(environment_host) catch {
    error =>
      return failure("error: invalid current directory: \{Repr(error)}", 1)
  } noraise {
    value => @project.ProjectInput::new(value, stdin~)
  }
  let context = try
    resolve_global_context(loading_host, environment_host, arguments, context)
  catch {
    error =>
      return if arguments.flag("quiet") {
        @cli.ApplicationResponse::new(b"", b"", error.exit_code())
      } else {
        failure(error.message(), error.exit_code())
      }
  } noraise {
    value => value
  }
  match arguments.command() {
    RunCommand => {
      let process = @host_process.ProcessAdapter::new(
        cygpath=arguments.value("cygpath").unwrap(),
      )
      execute_run(
        loading_host,
        execution_host,
        environment_host,
        process,
        arguments,
        context,
        default_list=true,
      )
    }
    ChooseCommand => {
      let process = @host_process.ProcessAdapter::new(
        cygpath=arguments.value("cygpath").unwrap(),
      )
      let selections = try
        execute_choose_command_async(
          loading_host, environment_host, process, arguments, context,
        )
      catch {
        error => return application_failure(arguments, context, error)
      } noraise {
        value => value
      }
      let stdout : Array[Byte] = []
      let stderr : Array[Byte] = []
      for selection in selections {
        let response = execute_run(
          loading_host,
          execution_host,
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
    }
    EditCommand => {
      let process = @host_process.ProcessAdapter::new(
        cygpath=arguments.value("cygpath").unwrap(),
      )
      try
        execute_edit_command_async(
          loading_host, environment_host, process, arguments, context,
        )
      catch {
        error => application_failure(arguments, context, error)
      } noraise {
        value => value
      }
    }
    CleanCommand =>
      try execute_clean_command(loading_host, arguments, context) catch {
        error => application_failure(arguments, context, error)
      } noraise {
        value => value
      }
    CheckCommand | FormatCommand | InitCommand =>
      try
        execute_file_command(loading_host, environment_host, arguments, context)
      catch {
        error => application_failure(arguments, context, error)
      } noraise {
        value => value
      }
    EvaluateCommand => {
      let process = @host_process.ProcessAdapter::new(
        cygpath=arguments.value("cygpath").unwrap(),
      )
      try
        execute_evaluate_command_async(
          loading_host, environment_host, process, arguments, context,
        )
      catch {
        error => application_failure(arguments, context, error)
      } noraise {
        value => value
      }
    }
    CommandCommand => {
      let process = @host_process.ProcessAdapter::new(
        cygpath=arguments.value("cygpath").unwrap(),
      )
      try
        execute_command_command_async(
          loading_host, environment_host, process, arguments, context,
        )
      catch {
        error => application_failure(arguments, context, error)
      } noraise {
        value => value
      }
    }
    DumpCommand | JsonCommand =>
      try
        execute_inspect_command(
          loading_host,
          arguments,
          context,
          environment=environment.entries,
        )
      catch {
        error => application_failure(arguments, context, error)
      } noraise {
        value => value
      }
    _ =>
      try
        execute_query_command(
          loading_host, environment_host, arguments, context,
        )
      catch {
        error => application_failure(arguments, context, error)
      } noraise {
        value => value
      }
  }
}
