///|
priv struct InvocationEnvironment {
  entries : Array[(String, String)]
  values : Map[String, String]
}

///|
/// Optional coarse-grained timing for remote performance experiments. The
/// default path does not allocate this record or write diagnostics.
priv struct PerfTrace {
  started : Int64
  events : Array[(String, Int64)]
}

///|
fn perf_trace_new() -> PerfTrace? {
  match @env.get_env_var("MOONJUST_PERF_TRACE") {
    Some("1") => Some({ started: @async.now(), events: [], })
    _ => None
  }
}

///|
fn PerfTrace::mark(self : PerfTrace, name : String) -> Unit {
  self.events.push((name, @async.now() - self.started))
}

///|
async fn PerfTrace::emit(self : PerfTrace) -> Unit {
  let fields : Array[String] = []
  for event in self.events {
    fields.push(
      "{\"stage\":\"" +
      event.0 +
      "\",\"elapsed_ms\":" +
      event.1.to_string() +
      "}",
    )
  }
  try
    @stdio.stderr.write(
      @utf8.encode(
        "MOONJUST_PERF_TRACE {\"events\":[" + fields.join(",") + "]}\n",
      ),
    )
  catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
fn perf_trace_mark(trace : PerfTrace?, name : String) -> Unit {
  match trace {
    Some(value) => value.mark(name)
    None => ()
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
fn init {
  // The native launcher must install the process-wide signal disposition
  // before the async root task starts. Static requests still avoid all host
  // and process setup in `main`, but retain this compatibility policy.
  @host_process.prepare_signal_forwarding()
}

///|
fn[E : @host.HostEnv] parse_environment(
  environment_host : E,
) -> InvocationEnvironment raise @host.HostError {
  let entries = @host.HostEnv::env_entries(environment_host)
  let environment : Map[String, String] = Map([])
  for entry in entries {
    environment[entry.0] = entry.1
  }
  { entries, values: environment, }
}

///|
priv enum PreparedInvocation {
  Ready(@cli.CliArguments, InvocationEnvironment)
  Respond(@cli.ApplicationResponse)
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
const MOONJUST_CHANGELOG : String =
  #|Changelog
  #|=========
  #|
  #|MoonJust maintains its own release history independently of upstream just.
  #|This build targets compatibility with just 1.57.0.

///|
const JUST_MAN_HEADER : String =
  #|.TH just 1
  #|.SH NAME
  #|just \- a command runner for project-specific tasks
  #|.SH SYNOPSIS
  #|.B just
  #|[options] [recipe [arguments...]]

///|
fn static_invocation_response(
  argv : ArrayView[String],
) -> @cli.ApplicationResponse? {
  if argv.length() != 1 {
    return None
  }
  match argv[0] {
    "--help" | "-h" =>
      Some(
        @cli.ApplicationResponse::success(
          stdout=@utf8.encode(@cli.render_help()),
        ),
      )
    "--version" | "-V" =>
      Some(
        @cli.ApplicationResponse::success(
          stdout=@utf8.encode(@moonjust.version_line() + "\n"),
        ),
      )
    "--changelog" =>
      Some(
        @cli.ApplicationResponse::success(
          stdout=@utf8.encode(MOONJUST_CHANGELOG + "\n"),
        ),
      )
    "--man" =>
      Some(
        @cli.ApplicationResponse::success(
          stdout=@utf8.encode(JUST_MAN_HEADER + "\n"),
        ),
      )
    _ => None
  }
}

///|
async fn read_stdin_source_bounded(max_bytes : Int) -> Bytes {
  let read_limit = max_bytes + 1
  let result = Buffer(size_hint=Int::min(read_limit, 64 * 1024))
  while result.length() < read_limit {
    let remaining = read_limit - result.length()
    guard @stdio.stdin.read_some(max_len=Int::min(remaining, 64 * 1024))
      is Some(chunk) else {
      break
    }
    if chunk.is_empty() {
      break
    }
    result.write_bytes(chunk)
  }
  result.to_bytes()
}

///|
async fn request_response(
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
  match request {
    String("signal") =>
      return Some(
        match @host_process.wait_for_signal_request() {
          Some(signal) =>
            @cli.ApplicationResponse::success(
              stdout=@utf8.encode("{\"signal\":\"" + signal + "\"}"),
            )
          None =>
            failure(
              "error: signal observation is unavailable in async-only mode", 2,
            )
        },
      )
    _ => ()
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
async fn[E : @host.HostEnv + @host.HostPlatform] prepare_invocation(
  environment_host : E,
  argv : ArrayView[String],
  trace? : PerfTrace? = None,
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
  perf_trace_mark(trace, "cli.environment")
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
  perf_trace_mark(trace, "cli.parse")
  Ready(arguments, environment)
}

///|
async fn[F : @host.HostFs + @host.HostSourceReader] application_failure(
  host : F,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
  error : @application.ApplicationError,
) -> @cli.ApplicationResponse {
  let response = failure(
    @application.render_application_error_async(host, arguments, context, error),
    error.exit_code(),
  )
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
// Target-specific adapters keep native-only synchronous commands out of the
// async state-machine graph while wasm retains bounded async I/O.
#cfg(target="native")
fn[
  F : @host.HostFs,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] dispatch_default_list(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
) -> @cli.ApplicationResponse? raise @application.ApplicationError {
  @application.execute_default_list_command(
    host, terminal_host, arguments, context,
  )
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[
  F : @host.HostFs + @host.HostSourceReader,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] dispatch_default_list(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
) -> @cli.ApplicationResponse? raise @application.ApplicationError {
  @application.execute_default_list_command_async(
    host, terminal_host, arguments, context,
  )
}

///|
#cfg(target="native")
fn[F : @host.HostFs] dispatch_inspect(
  host : F,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
  environment : ArrayView[(String, String)],
) -> @cli.ApplicationResponse raise @application.ApplicationError {
  @application.execute_inspect_command(host, arguments, context, environment~)
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[F : @host.HostFs + @host.HostSourceReader] dispatch_inspect(
  host : F,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
  environment : ArrayView[(String, String)],
) -> @cli.ApplicationResponse raise @application.ApplicationError {
  @application.execute_inspect_command_async(
    host,
    arguments,
    context,
    environment~,
  )
}

///|
#cfg(target="native")
fn[
  F,
  T : @host.HostFs + @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] dispatch_query(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
) -> @cli.ApplicationResponse raise @application.ApplicationError {
  ignore(host)
  @application.execute_query_command(terminal_host, arguments, context)
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[
  F : @host.HostFs + @host.HostSourceReader,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] dispatch_query(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
) -> @cli.ApplicationResponse raise @application.ApplicationError {
  @application.execute_query_command_with_terminal_async(
    host, terminal_host, arguments, context,
  )
}

///|
#warnings("-unused_trait_bound")
async fn[
  F : @host.HostFs + @host.HostSourceReader + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  E : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
  P : @host.HostAsyncProcess + @host.HostAsyncOutput,
] execute_run(
  loading_host : F,
  execution_host : F,
  environment_host : E,
  process : P,
  arguments : @cli.CliArguments,
  context : @application.ApplicationContext,
  trace? : PerfTrace? = None,
) -> @cli.ApplicationResponse {
  let plan = try
    @application.plan_run_command_async(
      loading_host, environment_host, process, arguments, context,
    )
  catch {
    error => return application_failure(loading_host, arguments, context, error)
  } noraise {
    value => value
  }
  perf_trace_mark(trace, "application.plan")
  if !arguments.flag("yes") {
    match confirm_execution(plan) {
      Some(response) => return response
      None => ()
    }
  }
  if !arguments.flag("dry-run") {
    // The portable loader cache is discarded at the execution boundary.
    // Recipes may rewrite any path that was inspected while planning.
    ignore(runtime_environment_host())
  }
  let summary = try
    @runtime.execute_plan_live(
      process, process, execution_host, environment_host, plan,
    )
  catch {
    error =>
      return if arguments.flag("quiet") || !error.show_message() {
        @cli.ApplicationResponse::new(b"", b"", error.exit_code())
      } else {
        let message = match error.error() {
          Evaluation(evaluation) =>
            @application.render_application_error_async(
              loading_host,
              arguments,
              context,
              Evaluation(evaluation),
            )
          _ => error.message()
        }
        failure(message, error.exit_code())
      }
  } noraise {
    value => value
  }
  perf_trace_mark(trace, "runtime.execute")
  if summary.commands() >= 0 {
    @cli.ApplicationResponse::success()
  } else {
    failure("error: invalid live execution summary", 1)
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
#warnings("-unused_trait_bound")
async fn[
  F : @host.HostFs + @host.HostSourceReader + @host.HostTemp + @host.HostAtomicFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  E : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] run_prepared_cli(
  loading_host : F,
  execution_host : F,
  environment_host : E,
  arguments : @cli.CliArguments,
  environment : InvocationEnvironment,
  stdin : Bytes,
  trace? : PerfTrace? = None,
) -> @cli.ApplicationResponse {
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
  if arguments.command() == ChangelogCommand {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(MOONJUST_CHANGELOG + "\n"),
    )
  }
  if arguments.command() == ManCommand {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(JUST_MAN_HEADER + "\n"),
    )
  }
  let cwd = try @host.HostEnv::current_dir(environment_host) catch {
    error =>
      return failure("error: invalid current directory: \{Repr(error)}", 1)
  } noraise {
    value => value
  }
  let context = @application.ApplicationContext::new(cwd, stdin~)
  perf_trace_mark(trace, "application.context")
  let context = try
    @application.resolve_global_context(
      loading_host, environment_host, arguments, context,
    )
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
  if arguments.command() == RunCommand {
    perf_trace_mark(trace, "application.dispatch")
    let default_list = try
      dispatch_default_list(loading_host, environment_host, arguments, context)
    catch {
      error =>
        return application_failure(loading_host, arguments, context, error)
    } noraise {
      value => value
    }
    match default_list {
      Some(response) => return response
      None => ()
    }
    let process = @host_process.ProcessAdapter::new()
    execute_run(
      loading_host,
      execution_host,
      environment_host,
      process,
      arguments,
      context,
      trace~,
    )
  } else if arguments.command() == ChooseCommand {
    perf_trace_mark(trace, "application.dispatch")
    let process = @host_process.ProcessAdapter::new()
    let selections = try
      @application.execute_choose_command_async(
        loading_host, environment_host, process, arguments, context,
      )
    catch {
      error =>
        return application_failure(loading_host, arguments, context, error)
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
        trace~,
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
    perf_trace_mark(trace, "application.dispatch")
    let process = @host_process.ProcessAdapter::new()
    try
      @application.execute_edit_command_async(
        loading_host, environment_host, process, arguments, context,
      )
    catch {
      error => application_failure(loading_host, arguments, context, error)
    } noraise {
      response => response
    }
  } else if arguments.command() == CleanCommand {
    perf_trace_mark(trace, "application.dispatch")
    try
      @application.execute_clean_command(loading_host, arguments, context)
    catch {
      error => application_failure(loading_host, arguments, context, error)
    } noraise {
      response => response
    }
  } else if arguments.command() == CheckCommand ||
    arguments.command() == FormatCommand ||
    arguments.command() == InitCommand {
    perf_trace_mark(trace, "application.dispatch")
    try
      @application.execute_file_command_async(loading_host, arguments, context)
    catch {
      error => application_failure(loading_host, arguments, context, error)
    } noraise {
      response => response
    }
  } else if arguments.command() == EvaluateCommand {
    perf_trace_mark(trace, "application.dispatch")
    let process = @host_process.ProcessAdapter::new()
    try
      @application.execute_evaluate_command_async(
        loading_host, environment_host, process, arguments, context,
      )
    catch {
      error => application_failure(loading_host, arguments, context, error)
    } noraise {
      response => response
    }
  } else if arguments.command() == CommandCommand {
    perf_trace_mark(trace, "application.dispatch")
    let process = @host_process.ProcessAdapter::new()
    try
      @application.execute_command_command_async(
        loading_host, environment_host, process, arguments, context,
      )
    catch {
      error => application_failure(loading_host, arguments, context, error)
    } noraise {
      response => response
    }
  } else if arguments.command() == DumpCommand ||
    arguments.command() == JsonCommand {
    perf_trace_mark(trace, "application.dispatch")
    try
      dispatch_inspect(loading_host, arguments, context, environment.entries)
    catch {
      error => application_failure(loading_host, arguments, context, error)
    } noraise {
      response => response
    }
  } else {
    perf_trace_mark(trace, "application.dispatch")
    try
      dispatch_query(loading_host, environment_host, arguments, context)
    catch {
      error => application_failure(loading_host, arguments, context, error)
    } noraise {
      response => response
    }
  }
}

///|
async fn[
  F : @host.HostFs + @host.HostSourceReader + @host.HostTemp + @host.HostAtomicFs + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  E : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] run_cli(
  host : F,
  environment_host : E,
  argv : ArrayView[String],
  stdin : Bytes,
) -> @cli.ApplicationResponse {
  match prepare_invocation(environment_host, argv) {
    Respond(response) => response
    Ready(arguments, environment) =>
      run_prepared_cli(
        host, host, environment_host, arguments, environment, stdin,
      )
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
fn command_may_spawn_process(command : @cli.CommandKind) -> Bool {
  match command {
    RunCommand
    | ChooseCommand
    | EditCommand
    | EvaluateCommand
    | CommandCommand => true
    _ => false
  }
}

///|
async fn main {
  let raw_argv = @env.args()
  let argv = raw_argv[1:]
  // Construct the filesystem adapter before the environment snapshot. The
  // portable adapter resets its invocation-local snapshots on construction.
  let host = runtime_host()
  let environment_host = runtime_environment_host()
  match static_invocation_response(argv) {
    Some(response) => emit_response(response)
    None => {
      let trace = perf_trace_new()
      match prepare_invocation(environment_host, argv, trace~) {
        Respond(response) => emit_response(response)
        Ready(arguments, environment) => {
          let stdin = if !arguments.flag("help") &&
            !arguments.flag("version") &&
            arguments.value("justfile") == Some("-") {
            read_stdin_source_bounded(
              @lexer.LexerLimits::default().max_source_bytes(),
            ) catch {
              _ => b""
            }
          } else {
            b""
          }
          let execution_host = if (
              arguments.command() == RunCommand ||
              arguments.command() == ChooseCommand
            ) &&
            !arguments.flag("dry-run") {
            // Keep execution reads isolated from the planning/load cache.
            runtime_host()
          } else {
            host
          }
          let response = if command_may_spawn_process(arguments.command()) {
            @async.with_task_group() <| group => {
              // Signal setup is only needed on paths that may start a child.
              ignore(@host_process.configure_signal_forwarding(group, false))
              run_prepared_cli(
                host,
                execution_host,
                environment_host,
                arguments,
                environment,
                stdin,
                trace~,
              )
            }
          } else {
            run_prepared_cli(
              host,
              execution_host,
              environment_host,
              arguments,
              environment,
              stdin,
              trace~,
            )
          }
          match trace {
            Some(value) => {
              value.mark("application.complete")
              value.emit()
            }
            None => ()
          }
          emit_response(response)
        }
      }
    }
  }
}

///|
fn test_host(windows : Bool) -> @host.FakeHost {
  let flavor = if windows { @path.Windows } else { Unix }
  let operating_system = if windows { @host.Windows } else { Linux }
  @host.FakeHost::new(
    try! @path.PathValue::new(
      if windows {
        "C:\\workspace"
      } else {
        "/workspace"
      },
      flavor,
    ),
    @host.PlatformInfo::new(operating_system, "test", flavor),
  )
}

///|
async test "cli renders help and release metadata without process access" {
  let host = test_host(false)
  host.deny(Process)
  let help = run_cli(host, host, ["--help"], b"")
  assert_eq(help.exit_code(), 0)
  assert_true((try! @utf8.decode(help.stdout())).contains("Usage:"))
  let version = run_cli(host, host, ["--version"], b"")
  assert_eq(version.exit_code(), 0)
  assert_eq(version.stdout(), @utf8.encode(@moonjust.version_line() + "\n"))
  let changelog = run_cli(host, host, ["--changelog"], b"")
  assert_eq(changelog.exit_code(), 0)
  assert_true((try! @utf8.decode(changelog.stdout())).contains("MoonJust"))
  let man = run_cli(host, host, ["--man"], b"")
  assert_eq(man.exit_code(), 0)
  assert_true((try! @utf8.decode(man.stdout())).contains(".TH just 1"))
  assert_eq(host.process_calls().length(), 0)
}

///|
async test "single static options do not enumerate the environment" {
  let host = test_host(false)
  host.deny(Environment)
  for option in ["--help", "-h", "--version", "-V", "--changelog", "--man"] {
    assert_eq(run_cli(host, host, [option], b"").exit_code(), 0)
  }
  assert_eq(run_cli(host, host, ["--version", "extra"], b"").exit_code(), 1)
}

///|
async test "cli request returns platform encoded environment values" {
  let unix = test_host(false)
  unix.set_env("MOONJUST_TEST", "aé")
  let unix_response = run_cli(
    unix,
    unix,
    ["--request", "{\"environment-variable\":\"MOONJUST_TEST\"}"],
    b"",
  )
  assert_eq(unix_response.exit_code(), 0)
  assert_eq(
    unix_response.stdout(),
    b"{\"environment-variable\":{\"Unix\":[97,195,169]}}",
  )

  let windows = test_host(true)
  windows.set_env("MOONJUST_TEST", "a😀")
  let windows_response = run_cli(
    windows,
    windows,
    ["--request", "{\"environment-variable\":\"MOONJUST_TEST\"}"],
    b"",
  )
  assert_eq(windows_response.exit_code(), 0)
  assert_eq(
    windows_response.stdout(),
    b"{\"environment-variable\":{\"Windows\":[97,55357,56832]}}",
  )
}

///|
async test "cli rejects malformed and unsupported requests" {
  let host = test_host(false)
  let malformed = run_cli(host, host, ["--request", "{"], b"")
  assert_eq(malformed.exit_code(), 2)
  assert_eq(malformed.stderr(), b"error: invalid request\n")
  let unsupported = run_cli(host, host, ["--request", "[]"], b"")
  assert_eq(unsupported.exit_code(), 2)
  assert_eq(unsupported.stderr(), b"error: invalid request\n")
  let missing = run_cli(
    host,
    host,
    ["--request", "{\"environment-variable\":\"MISSING\"}"],
    b"",
  )
  assert_eq(missing.exit_code(), 0)
  assert_eq(missing.stdout(), b"{\"environment-variable\":null}")
}

///|
async test "cli signal request reports async-only policy" {
  let response = run_cli(
    test_host(false),
    test_host(false),
    ["--request", "\"signal\""],
    b"",
  )
  assert_eq(response.exit_code(), 2)
  assert_eq(
    response.stderr(),
    b"error: signal observation is unavailable in async-only mode\n",
  )
}

///|
test "response helpers preserve both output streams" {
  let stdout : Array[Byte] = []
  let stderr : Array[Byte] = []
  append_response(
    stdout,
    stderr,
    @cli.ApplicationResponse::new(b"out", b"err", 3),
  )
  assert_eq(Bytes::from_array(stdout), b"out")
  assert_eq(Bytes::from_array(stderr), b"err")
  let failed = failure("error: bad\n", 2)
  assert_eq(failed.exit_code(), 2)
  assert_eq(failed.stderr(), b"error: bad\n")
}

///|
async test "cli dispatch matrix covers file query inspect and cache commands" {
  let host = test_host(false)
  host.put_file(
    try! @path.PathValue::new("/workspace/justfile", Unix),
    b"value := 'ci'\n[group('build')]\nroot:\n",
  )
  let cases = [
    (["--fmt", "--check"], ""),
    (["--fmt", "--dry-run"], ""),
    (["--list"], "root"),
    (["--summary"], "root"),
    (["--variables"], "value"),
    (["--groups"], "build"),
    (["--show", "root"], "root"),
    (["--usage", "root"], "Usage"),
    (["--json"], "recipes"),
    (["--dump"], "value"),
    (["--evaluate", "value"], "ci"),
    (["--clean"], ""),
  ]
  for row in cases {
    let response = run_cli(host, host, row.0, b"")
    assert_eq(response.exit_code(), 0)
    if !row.1.is_empty() {
      assert_true((try! @utf8.decode(response.stdout())).contains(row.1))
    }
  }

  let stdin = run_cli(
    host,
    host,
    ["--justfile", "-", "--list"],
    b"stdin-recipe:\n",
  )
  assert_eq(stdin.exit_code(), 0)
  assert_true((try! @utf8.decode(stdin.stdout())).contains("stdin-recipe"))
}

///|
async test "cli dispatch matrix preserves parse and application failures" {
  let host = test_host(false)
  host.put_file(
    try! @path.PathValue::new("/workspace/justfile", Unix),
    b"root:\n",
  )
  let invalid = run_cli(host, host, ["--definitely-invalid"], b"")
  assert_eq(invalid.exit_code(), 2)
  assert_true(invalid.stderr().length() > 0)

  let missing = run_cli(host, host, ["missing"], b"")
  assert_true(missing.exit_code() != 0)
  assert_true((try! @utf8.decode(missing.stderr())).contains("missing"))
  let quiet = run_cli(host, host, ["--quiet", "missing"], b"")
  assert_true(quiet.exit_code() != 0)
  assert_eq(quiet.stderr(), b"")

  let malformed = test_host(false)
  malformed.put_file(
    try! @path.PathValue::new("/workspace/justfile", Unix),
    b"root:\n not-indented\n",
  )
  let checked = run_cli(malformed, malformed, ["--fmt", "--check"], b"")
  assert_true(checked.exit_code() != 0)
  assert_true(checked.stderr().length() > 0)
}

///|
#coverage.skip
#cfg(platform="windows")
fn successful_command_argv() -> Array[String] {
  ["--command", "cmd.exe", "/d", "/c", "exit 0"]
}

///|
#cfg(not(platform="windows"))
fn successful_command_argv() -> Array[String] {
  ["--command", "/usr/bin/true"]
}

///|
#coverage.skip
#cfg(platform="windows")
fn failed_command_argv() -> Array[String] {
  ["--command", "cmd.exe", "/d", "/c", "exit 1"]
}

///|
#cfg(not(platform="windows"))
fn failed_command_argv() -> Array[String] {
  ["--command", "/usr/bin/false"]
}

///|
#coverage.skip
#cfg(platform="windows")
fn command_test_host() -> @host.FakeHost {
  let current = @env.current_dir().unwrap_or(".")
  @host.FakeHost::new(
    try! @path.PathValue::new(current, Windows),
    @host.PlatformInfo::new(Windows, "test", Windows),
  )
}

///|
#cfg(not(platform="windows"))
fn command_test_host() -> @host.FakeHost {
  let current = @env.current_dir().unwrap_or(".")
  @host.FakeHost::new(
    try! @path.PathValue::new(current, Unix),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
}

///|
#coverage.skip
#cfg(platform="windows")
fn command_test_justfile_path(current : String) -> @path.PathValue {
  try! @path.PathValue::new(current, Windows).join(
    try! @path.PathValue::new("justfile", Windows),
  )
}

///|
#cfg(not(platform="windows"))
fn command_test_justfile_path(current : String) -> @path.PathValue {
  try! @path.PathValue::new(current, Unix).join(
    try! @path.PathValue::new("justfile", Unix),
  )
}

///|
async test "cli dispatch covers successful run initialization and arbitrary commands" {
  let run_host = test_host(false)
  run_host.put_file(
    try! @path.PathValue::new("/workspace/justfile", Unix),
    b"root:\n",
  )
  let run = run_cli(run_host, run_host, ["root"], b"")
  assert_eq(run.exit_code(), 0)
  assert_eq(run.stderr(), b"")

  let init_host = test_host(false)
  let initialized = run_cli(init_host, init_host, ["--init"], b"")
  assert_eq(initialized.exit_code(), 0)
  assert_true(
    @host.HostFs::file_exists(
      init_host,
      try! @path.PathValue::new("/workspace/justfile", Unix),
    ),
  )

  let command_host = command_test_host()
  let current = @env.current_dir().unwrap_or(".")
  command_host.put_file(
    command_test_justfile_path(current),
    b"export TOKEN := 'coverage'\n",
  )
  let command = run_cli(
    command_host,
    command_host,
    successful_command_argv(),
    b"",
  )
  if command.exit_code() != 0 {
    fail("unexpected command failure: \{Repr(command.stderr().to_owned())}")
  }
  let failed = run_cli(command_host, command_host, failed_command_argv(), b"")
  assert_true(failed.exit_code() != 0)
  assert_true((try! @utf8.decode(failed.stderr())).contains("command"))
}
