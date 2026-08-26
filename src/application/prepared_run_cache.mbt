///|
/// A portable CLI run checks `default-list` immediately before planning. Keep
/// that immutable load result for the following planner call so Wasm does not
/// parse and compile the same project twice.
priv struct PreparedRunProject {
  cwd : @path.PathValue
  stdin : BytesView
  source_id : @source.SourceId
  global_justfile : @path.PathValue?
  global_project_directory : @path.PathValue?
  justfile : String?
  working_directory : String?
  justfile_name : String?
  ceiling : String?
  global : Bool
  unstable : Bool
  platform : @host.PlatformInfo
  environment : ArrayView[(String, String)]
  graph : @loader.LoadedGraph
  directories : @workdir.WorkingDirectoryModel
  project : @semantic.ProjectCompilation
}

///|
let prepared_run_project_cache : Ref[PreparedRunProject?] = Ref(None)

///|
fn clear_prepared_run_project() -> Unit {
  prepared_run_project_cache.val = None
}

///|
fn prepared_run_matches(
  prepared : PreparedRunProject,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
  platform : @host.PlatformInfo,
  environment : ArrayView[(String, String)],
) -> Bool {
  prepared.cwd == context.cwd() &&
  prepared.stdin == context.stdin() &&
  prepared.source_id == context.source_id() &&
  prepared.global_justfile == context.global_justfile() &&
  prepared.global_project_directory == context.global_project_directory() &&
  prepared.justfile == arguments.value("justfile") &&
  prepared.working_directory == arguments.value("working-directory") &&
  prepared.justfile_name == arguments.value("justfile-name") &&
  prepared.ceiling == arguments.value("ceiling") &&
  prepared.global == arguments.flag("global-justfile") &&
  prepared.unstable == arguments.flag("unstable") &&
  prepared.platform == platform &&
  prepared.environment == environment
}

///|
fn cache_prepared_run_project(
  arguments : @cli.CliArguments,
  context : ApplicationContext,
  platform : @host.PlatformInfo,
  environment : ArrayView[(String, String)],
  graph : @loader.LoadedGraph,
  directories : @workdir.WorkingDirectoryModel,
  project : @semantic.ProjectCompilation,
) -> Unit {
  if !platform.portable_runtime() {
    return
  }
  prepared_run_project_cache.val = Some({
    cwd: context.cwd(),
    stdin: context.stdin(),
    source_id: context.source_id(),
    global_justfile: context.global_justfile(),
    global_project_directory: context.global_project_directory(),
    justfile: arguments.value("justfile"),
    working_directory: arguments.value("working-directory"),
    justfile_name: arguments.value("justfile-name"),
    ceiling: arguments.value("ceiling"),
    global: arguments.flag("global-justfile"),
    unstable: arguments.flag("unstable"),
    platform,
    environment,
    graph,
    directories,
    project,
  })
}

///|
fn take_prepared_run_project(
  arguments : @cli.CliArguments,
  context : ApplicationContext,
  platform : @host.PlatformInfo,
  environment : ArrayView[(String, String)],
) -> (
  @loader.LoadedGraph,
  @workdir.WorkingDirectoryModel,
  @semantic.ProjectCompilation,
)? {
  let cached = prepared_run_project_cache.val
  clear_prepared_run_project()
  match cached {
    Some(value) if prepared_run_matches(
        value, arguments, context, platform, environment,
      ) => Some((value.graph, value.directories, value.project))
    _ => None
  }
}
