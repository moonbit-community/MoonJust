///|
#cfg(target="native")
fn[T : @host.HostFs] execute_inspect_command(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  environment? : ArrayView[(String, String)] = [],
) -> @cli.ApplicationResponse raise ApplicationError {
  let (graph, _) = load_graph_input_with_directories(
    host,
    arguments,
    context,
    environment~,
  )
  let loaded = graph.files()[0]
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
  )
  let compilation = project.root()
  let output = match arguments.command() {
    EvaluateCommand => evaluate_text(compilation, loaded.ast(), arguments)
    DumpCommand if arguments.value("dump-format") == Some("json") =>
      inspect_json(loaded, compilation, project~, graph~).stringify() + "\n"
    DumpCommand => {
      let indentation = formatting_indentation(arguments, loaded.ast())
      @formatter.format_with_indentation(loaded.ast(), indentation) catch {
        error => raise Format(error)
      }
    }
    JsonCommand =>
      inspect_json(loaded, compilation, project~, graph~).stringify() + "\n"
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output))
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
#warnings("-unused_async-unused_trait_bound")
async fn[T : @host.HostFs + @host.HostSourceReader] execute_inspect_command_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  environment? : ArrayView[(String, String)] = [],
) -> @cli.ApplicationResponse raise ApplicationError {
  let (graph, _) = load_graph_input_with_directories_async(
    host,
    arguments,
    context,
    environment~,
  )
  let loaded = graph.files()[0]
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
  )
  let compilation = project.root()
  let output = match arguments.command() {
    EvaluateCommand => evaluate_text(compilation, loaded.ast(), arguments)
    DumpCommand if arguments.value("dump-format") == Some("json") =>
      inspect_json(loaded, compilation, project~, graph~).stringify() + "\n"
    DumpCommand => {
      let indentation = formatting_indentation(arguments, loaded.ast())
      @formatter.format_with_indentation(loaded.ast(), indentation) catch {
        error => raise Format(error)
      }
    }
    JsonCommand =>
      inspect_json(loaded, compilation, project~, graph~).stringify() + "\n"
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output))
}
