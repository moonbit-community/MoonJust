///|
using @query {
  closest_name,
  direct_submodule_names,
  loaded_for_module,
  private_assignments,
  unknown_submodule_message,
}

///|
fn application_query_error(error : @query.QueryError) -> ApplicationError {
  match error {
    Query(message) => Query(message)
    Evaluation(error) => Evaluation(error)
    UnsupportedCommand(command) => UnsupportedCommand(command)
  }
}

///|
fn query_response(result : @query.QueryResult) -> @cli.ApplicationResponse {
  @cli.ApplicationResponse::success(stdout=result.stdout, stderr=result.stderr)
}

///|
/// Project compilation is owned by `internal/project`; application only maps
/// its domain error into the response-oriented application error.
fn compile_loaded_graph(
  graph : @loader.LoadedGraph,
  allow_unstable~ : Bool = false,
  platform~ : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
) -> @semantic.ProjectCompilation raise ApplicationError {
  @project.compile_loaded_graph(graph, allow_unstable~, platform~) catch {
    error => raise ApplicationError::from_project_error(error)
  }
}
