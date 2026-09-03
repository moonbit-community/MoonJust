///|
#warnings("-unused_constructor")
priv enum ImmediateResult {
  NotHandled
  Handled
  Text(String)
}

///|
#cfg(all(target="native", not(platform="windows")))
fn init {
  @host_process.prepare_signal_forwarding()
}

///|
#cfg(all(target="native", platform="windows"))
fn init {
  configure_binary_standard_streams()
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
async fn async_main() -> Unit {
  let argv = @env.args()[1:]
  let host = runtime_host()
  let environment_host = runtime_environment_host()
  match @application.static_invocation_response(argv) {
    Some(response) => emit_response(response)
    None =>
      match @application.classify_request(environment_host, argv) {
        @application.Respond(response) => emit_response(response)
        @application.Ready(arguments, environment) => {
          let stdin = if arguments.value("justfile") == Some("-") {
            @application.read_stdin_source_bounded(
              @lexer.LexerLimits::default().max_source_bytes(),
            )
          } else {
            b""
          }
          let execution_host = if (
              arguments.command() == RunCommand ||
              arguments.command() == ChooseCommand
            ) &&
            !arguments.flag("dry-run") {
            runtime_host()
          } else {
            host
          }
          let response = if command_may_spawn_process(arguments.command()) {
            @async.with_task_group() <| group => {
              ignore(@host_process.configure_signal_forwarding(group, false))
              @application.run_prepared_cli(
                host, execution_host, environment_host, arguments, environment, stdin,
              )
            }
          } else {
            @application.run_prepared_cli(
              host, execution_host, environment_host, arguments, environment, stdin,
            )
          }
          emit_response(response)
        }
      }
  }
}

///|
fn main {
  let argv = @env.args()[1:]
  match @application.static_invocation_text(argv) {
    Some(text) => println(text)
    None =>
      match try_runtime_fast_path(argv) {
        Text(text) => println(text)
        Handled => ()
        NotHandled => @async.run_async_main(() => async_main())
      }
  }
}
