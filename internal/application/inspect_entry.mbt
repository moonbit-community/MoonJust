///|
async fn[T : @host.HostFs] execute_inspect_command(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  environment~ : ArrayView[(String, String)] = [],
) -> @cli.ApplicationResponse raise ApplicationError {
  let graph = load_project_sources(host, arguments, context, environment~).graph()
  try {
    let loaded = graph.files()[0]
    let project = compile_loaded_graph(
      graph,
      allow_unstable=arguments.flag("unstable"),
    )
    let compilation = project.root()
    let output = match (arguments.command(), arguments.value("dump-format")) {
      (EvaluateCommand, _) =>
        evaluate_text(compilation, loaded.ast(), arguments)
      (JsonCommand, _) | (DumpCommand, Some("json")) =>
        @query.inspect_json(loaded, compilation, project~, graph~).stringify() +
        "\n"
      (DumpCommand, _) => {
        let indentation = formatting_indentation(arguments, loaded.ast())
        @formatter.format_with_indentation(loaded.ast(), indentation) catch {
          error => raise ApplicationError::Format(error)
        }
      }
      (command, _) =>
        raise ApplicationError::UnsupportedCommand("\{Repr(command)}")
    }
    @cli.ApplicationResponse::success(stdout=@utf8.encode(output))
  } catch {
    error => raise error.with_project_sources(graph, context.cwd())
  }
}
