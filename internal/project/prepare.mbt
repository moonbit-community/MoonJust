///|
pub(all) enum SourceSelection {
  Search
  File(@path.PathValue)
  Stdin
} derive(Debug)

///|
/// Inputs required to load one project. This type is independent of CLI
/// representation so every caller shares discovery and directory semantics.
pub struct ProjectLoadRequest {
  input : ProjectInput
  selection : SourceSelection
  working_directory : @path.PathValue?
  filename : String
  ceiling : @path.PathValue?
  platform : @semantic.TargetPlatform
  environment : ArrayView[(String, String)]
}

///|
pub fn ProjectLoadRequest::new(
  input : ProjectInput,
  selection : SourceSelection,
  filename : String,
  platform : @semantic.TargetPlatform,
  environment : ArrayView[(String, String)],
  working_directory? : @path.PathValue,
  ceiling? : @path.PathValue,
) -> ProjectLoadRequest {
  {
    input,
    selection,
    working_directory,
    filename,
    ceiling,
    platform,
    environment,
  }
}

///|
priv struct ResolvedProjectInput {
  input : ProjectInput
  path : @path.PathValue?
  directories : @workdir.WorkingDirectoryModel
}

///|
fn justfile_directories(
  input : ProjectInput,
  path : @path.PathValue,
  working_directory : @path.PathValue?,
) -> @workdir.WorkingDirectoryModel raise ProjectError {
  @workdir.WorkingDirectoryModel::from_justfile(
    input.cwd(),
    path,
    working_directory~,
  ) catch {
    error => raise WorkingDirectory(error)
  }
}

///|
fn[T : @host.HostFs] resolve_project_input(
  host : T,
  request : ProjectLoadRequest,
) -> ResolvedProjectInput raise ProjectError {
  let input = request.input
  match input.global_justfile() {
    Some(path) => {
      let project_directory = input
        .global_project_directory()
        .unwrap_or(path.parent().unwrap_or(input.cwd()))
      let directories = @workdir.WorkingDirectoryModel::from_global_justfile(
        input.cwd(),
        path,
        project_directory,
      ) catch {
        error => raise WorkingDirectory(error)
      }
      { input, path: Some(path), directories, }
    }
    None =>
      match request.selection {
        Stdin => {
          let directories = @workdir.WorkingDirectoryModel::from_stdin(
            input.cwd(),
            working_directory=request.working_directory,
          ) catch {
            error => raise WorkingDirectory(error)
          }
          { input, path: None, directories, }
        }
        File(path) => {
          let directories = justfile_directories(
            input,
            path,
            request.working_directory,
          )
          { input, path: directories.justfile(), directories, }
        }
        Search => {
          let options = @loader.SearchOptions::new(
            filename=request.filename,
            ceiling=request.ceiling,
          )
          let path = @loader.discover(host, input.cwd(), options~) catch {
            error => raise Load(error)
          }
          let directories = justfile_directories(
            input,
            path,
            request.working_directory,
          )
          { input, path: Some(path), directories, }
        }
      }
  }
}

///|
pub fn[T : @host.HostFs] load_sources(
  host : T,
  request : ProjectLoadRequest,
) -> ProjectSources raise ProjectError {
  let resolved = resolve_project_input(host, request)
  let graph = match resolved.path {
    Some(path) =>
      @loader.load_graph(
        host,
        path,
        resolved.input.source_id(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
    None =>
      @loader.load_stdin_graph(
        host,
        resolved.input.stdin().to_owned(),
        resolved.input.source_id(),
        resolved.directories.project_directory(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
  }
  ProjectSources::new(graph, resolved.directories)
}

///|
pub fn[T : @host.HostFs] load_snapshot(
  host : T,
  request : ProjectLoadRequest,
  allow_unstable? : Bool = false,
) -> ProjectSnapshot raise ProjectError {
  let sources = load_sources(host, request)
  let compilation = compile_loaded_graph(
    sources.graph(),
    allow_unstable~,
    platform=request.platform,
  )
  ProjectSnapshot::new(sources.graph(), compilation, sources.directories())
}

///|
/// Portable hosts retain bounded asynchronous reads while sharing all path and
/// working-directory resolution with the synchronous loader.
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn[T : @host.HostFs + @host.HostSourceReader] load_sources_async(
  host : T,
  request : ProjectLoadRequest,
) -> ProjectSources raise ProjectError {
  let resolved = resolve_project_input(host, request)
  let graph = match resolved.path {
    Some(path) =>
      @loader.load_graph_async(
        host,
        path,
        resolved.input.source_id(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
    None =>
      @loader.load_stdin_graph_async(
        host,
        resolved.input.stdin().to_owned(),
        resolved.input.source_id(),
        resolved.directories.project_directory(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
  }
  ProjectSources::new(graph, resolved.directories)
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn[T : @host.HostFs + @host.HostSourceReader] load_snapshot_async(
  host : T,
  request : ProjectLoadRequest,
  allow_unstable? : Bool = false,
) -> ProjectSnapshot raise ProjectError {
  let sources = load_sources_async(host, request)
  let compilation = compile_loaded_graph(
    sources.graph(),
    allow_unstable~,
    platform=request.platform,
  )
  ProjectSnapshot::new(sources.graph(), compilation, sources.directories())
}

///|
#cfg(target="native")
pub fn[T : @host.HostFs] load_sources_async(
  host : T,
  request : ProjectLoadRequest,
) -> ProjectSources raise ProjectError {
  load_sources(host, request)
}

///|
#cfg(target="native")
pub fn[T : @host.HostFs] load_snapshot_async(
  host : T,
  request : ProjectLoadRequest,
  allow_unstable? : Bool = false,
) -> ProjectSnapshot raise ProjectError {
  load_snapshot(host, request, allow_unstable~)
}
