///|
/// A portable CLI run checks `default-list` immediately before planning. Keep
/// that immutable load result for the following planner call so Wasm does not
/// parse and compile the same project twice.
#cfg(any(target="wasm", target="wasm-gc", target="js"))
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
  snapshot : @project.ProjectSnapshot
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
let prepared_run_project_cache : Ref[PreparedRunProject?] = Ref(None)

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn clear_prepared_run_project() -> Unit {
  prepared_run_project_cache.val = None
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn prepared_run_matches(
  prepared : PreparedRunProject,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
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
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn cache_prepared_run_project(
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform : @host.PlatformInfo,
  environment : ArrayView[(String, String)],
  snapshot : @project.ProjectSnapshot,
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
    snapshot,
  })
}

///|
#cfg(target="native")
fn take_prepared_run_project(
  _arguments : @cli.CliArguments,
  _context : @project.ProjectInput,
  _platform : @host.PlatformInfo,
  _environment : ArrayView[(String, String)],
) -> @project.ProjectSnapshot? {
  None
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn take_prepared_run_project(
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform : @host.PlatformInfo,
  environment : ArrayView[(String, String)],
) -> @project.ProjectSnapshot? {
  let cached = prepared_run_project_cache.val
  clear_prepared_run_project()
  match cached {
    Some(value) if prepared_run_matches(
        value, arguments, context, platform, environment,
      ) => Some(value.snapshot)
    _ => None
  }
}
