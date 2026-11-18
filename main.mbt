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
  if response.exit_code() != 0 {
    @env.exit(response.exit_code())
  }
}

///|
async fn main {
  let argv = @env.args()[1:]
  let host = @host_wasm.ExecutionFs::new()
  match @application.static_invocation_response(argv) {
    Some(response) => emit_response(response)
    None =>
      match @application.classify_request(host, argv) {
        Respond(response) => emit_response(response)
        Ready(arguments, environment) => {
          let stdin = if arguments.value("justfile") == Some("-") {
            @application.read_stdin_source_bounded(
              @lexer.LexerLimits::default().max_source_bytes(),
            )
          } else {
            b""
          }
          if command_may_spawn_process(arguments.command()) {
            @host_process.configure_cancellation_signals()
          }
          emit_response(
            @application.run_prepared_cli(
              host, host, host, arguments, environment, stdin,
            ),
          )
        }
      }
  }
}
