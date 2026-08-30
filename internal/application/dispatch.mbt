///|
/// Dispatch one validated command without granting process capability.
pub fn[
  F : @host.HostFs + @host.HostTemp,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_command_with_terminal(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
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
    DumpCommand | JsonCommand | EvaluateCommand => {
      let environment = @host.HostEnv::env_entries(terminal_host) catch {
        error => raise Host(error)
      }
      execute_inspect_command(host, arguments, context, environment~)
    }
    ChooseCommand | EditCommand | CommandCommand =>
      raise UnsupportedCommand(
        "interactive command requires process capability",
      )
    CleanCommand =>
      raise UnsupportedCommand("cache clean requires async storage")
    ChangelogCommand | ManCommand =>
      raise UnsupportedCommand("static command requires CLI asset")
    RunCommand => {
      let environment = @host.HostEnv::env_entries(terminal_host) catch {
        error => raise Host(error)
      }
      let (graph, directories) = load_graph_input_with_directories(
        host,
        arguments,
        context,
        environment~,
      )
      let project = compile_loaded_graph(
        graph,
        allow_unstable=arguments.flag("unstable"),
      )
      let compilation = project.root()
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
pub fn[
  T : @host.HostFs + @host.HostTemp + @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_command(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  execute_command_with_terminal(host, host, arguments, context)
}
