///|
fn default_list_module_path(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
) -> @modulepath.ModulePath? {
  if arguments.is_empty() {
    return Some(@modulepath.ModulePath::root())
  }
  let requested = if arguments.length() == 1 {
    arguments[0]
  } else {
    arguments.join("::")
  }
  project.resolve_module(@modulepath.ModulePath::root(), requested)
}

///|
async fn[T : @host.HostTerminal] default_list_response(
  terminal_host : T,
  arguments : @cli.CliArguments,
  snapshot : @project.ProjectSnapshot,
) -> @cli.ApplicationResponse? raise ApplicationError {
  let project = snapshot.compilation()
  guard default_list_module_path(project, arguments.positional()) is Some(path) else {
    return None
  }
  let compilation = project.module_compilation(path).unwrap()
  if !arguments.flag("default-list") &&
    !compilation.settings().bool("default-list") {
    return None
  }
  validate_project_variable_overrides(project, arguments)
  let color = selected_color_active(terminal_host, arguments, Stdout)
  let request = @query.QueryRequest::default_list(path, arguments)
  let result = render_query(
    request,
    snapshot.graph(),
    project,
    color,
    arguments,
  )
  Some(query_response(result))
}

///|
fn render_query(
  request : @query.QueryRequest,
  graph : @loader.LoadedGraph,
  project : @semantic.ProjectCompilation,
  color : Bool,
  arguments : @cli.CliArguments,
) -> @query.QueryResult raise ApplicationError {
  let overrides = Map([])
  if !arguments.variable_overrides().is_empty() {
    for path in project.module_paths() {
      overrides[path] = project_variable_overrides(project, path, arguments)
    }
  }
  @query.render(request, graph, project, color, overrides~) catch {
    error => raise application_query_error(error)
  }
}

///|
async fn[
  F : @host.HostFs,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_query_command(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  let (arguments, context) = query_search_prefix(host, arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("query.platform")
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("query.environment")
  let graph = load_project_sources(
    host,
    arguments,
    context,
    platform=semantic_platform,
    environment=loading_environment,
  ).graph()
  perf_detail_mark("query.load")
  let result = try {
    match @query.try_fast_summary(graph, arguments) {
      Some(result) => result
      None => {
        let project = compile_loaded_graph(
          graph,
          allow_unstable=arguments.flag("unstable") ||
            arguments.command() == SummaryCommand,
          platform=semantic_platform,
        )
        perf_detail_mark("query.compile")
        validate_project_variable_overrides(project, arguments)
        let color = selected_color_active(terminal_host, arguments, Stdout)
        let request = @query.build_query(project, arguments) catch {
          error => raise application_query_error(error)
        }
        let result = render_query(request, graph, project, color, arguments)
        perf_detail_mark("query.render")
        result
      }
    }
  } catch {
    error => raise error.with_project_sources(graph, context.cwd())
  }
  ignore(perf_detail_emit() catch { _ => () })
  query_response(result)
}
