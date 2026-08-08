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
      let loaded = load_input(host, arguments, context)
      let compilation = compile_loaded(loaded)
      ignore(
        @invocation.parse_invocations(compilation, arguments.positional()) catch {
          error => raise Invocation(error)
        },
      )
      raise UnsupportedCommand("recipe execution")
    }
  }
}
