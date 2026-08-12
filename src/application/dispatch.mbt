///|
/// Dispatch one validated Phase 6 command without granting process capability.
pub fn[F : @host.HostFs + @host.HostTemp, T : @host.HostTerminal] execute_command_with_terminal(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  match arguments.command() {
    CheckCommand | FormatCommand | InitCommand =>
      execute_file_command(host, arguments, context)
    ListCommand
    | ShowCommand
    | SummaryCommand
    | UsageCommand
    | VariablesCommand
    | GroupsCommand =>
      execute_query_command_with_terminal(
        host, terminal_host, arguments, context,
      )
    DumpCommand | JsonCommand | EvaluateCommand =>
      execute_inspect_command(host, arguments, context)
    ChooseCommand | EditCommand =>
      raise UnsupportedCommand(
        "interactive command requires process capability",
      )
    CleanCommand =>
      raise UnsupportedCommand("cache clean requires async storage")
    RunCommand => {
      let (loaded, directories) = load_input_with_directories(
        host, arguments, context,
      )
      let compilation = compile_loaded(loaded)
      let overrides = variable_overrides(compilation, arguments)
      ignore(
        @invocation.parse_invocations(
          compilation,
          arguments.positional(),
          overrides~,
        ) catch {
          error => raise Invocation(error)
        },
      )
      ignore(directories)
      raise UnsupportedCommand("recipe execution")
    }
  }
}

///|
/// Dispatch with a single host that owns both filesystem and terminal facts.
pub fn[T : @host.HostFs + @host.HostTemp + @host.HostTerminal] execute_command(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  execute_command_with_terminal(host, host, arguments, context)
}
