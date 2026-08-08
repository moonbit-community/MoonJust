///|
/// Dispatch one validated Phase 6 command without granting process capability.
pub fn[T : @host.HostFs + @host.HostTemp] execute_command(
  host : T,
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
    | GroupsCommand => execute_query_command(host, arguments, context)
    DumpCommand | JsonCommand | EvaluateCommand =>
      execute_inspect_command(host, arguments, context)
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
