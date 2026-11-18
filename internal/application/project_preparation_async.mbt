///|
async fn[T : @host.HostFs] load_input_with_directories(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> (@loader.LoadedSource, @workdir.WorkingDirectoryModel) raise ApplicationError {
  if arguments.flag("global-justfile") {
    let (path, directories) = global_input_directories(context)
    let loaded = @loader.load(host, path, context.source_id()) catch {
      error => raise Load(error)
    }
    return (loaded, directories)
  }
  let working_directory = working_directory_argument(
    arguments,
    context.cwd().flavor(),
  )
  match input_selection(arguments, context.cwd().flavor()) {
    Stdin => {
      let directories = @workdir.WorkingDirectoryModel::from_stdin(
        context.cwd(),
        working_directory~,
      ) catch {
        error => raise WorkingDirectory(error)
      }
      let loaded = @loader.load_stdin(
        context.stdin().to_owned(),
        context.source_id(),
      ) catch {
        error => raise Load(error)
      }
      (loaded, directories)
    }
    File(path) => {
      let directories = @workdir.WorkingDirectoryModel::from_justfile(
        context.cwd(),
        path,
        working_directory~,
      ) catch {
        error => raise WorkingDirectory(error)
      }
      let resolved = directories.justfile().unwrap()
      let loaded = @loader.load(host, resolved, context.source_id()) catch {
        error => raise Load(error)
      }
      (loaded, directories)
    }
    Search => {
      let options = @loader.SearchOptions::new(
        filename=arguments.value("justfile-name").unwrap_or("justfile"),
        ceiling=ceiling_argument(arguments, context.cwd()),
      )
      let path = @loader.discover(host, context.cwd(), options~) catch {
        error => raise Load(error)
      }
      let directories = @workdir.WorkingDirectoryModel::from_justfile(
        context.cwd(),
        path,
      ) catch {
        error => raise WorkingDirectory(error)
      }
      let loaded = @loader.load(host, path, context.source_id()) catch {
        error => raise Load(error)
      }
      (loaded, directories)
    }
  }
}

///|
async fn[T : @host.HostFs] load_input(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @loader.LoadedSource raise ApplicationError {
  load_input_with_directories(host, arguments, context).0
}

///|
async fn[T : @host.HostFs] load_graph_input_with_directories(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform~ : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
  environment~ : ArrayView[(String, String)] = [],
) -> (@loader.LoadedGraph, @workdir.WorkingDirectoryModel) raise ApplicationError {
  let request = project_load_request(arguments, context, platform, environment)
  let sources = @project.load_sources(host, request) catch {
    Load(error) => raise Load(error)
    Path(error) => raise Path(error)
    WorkingDirectory(error) => raise WorkingDirectory(error)
    Semantic(error) => raise Semantic(error)
    Compilation(error) => raise Project(error)
  }
  (sources.graph(), sources.directories())
}

///|
/// Keep asynchronous project preparation behind the project boundary. The
/// application layer only translates CLI arguments into a load request and
/// maps the project-owned errors into its response vocabulary.
async fn[T : @host.HostFs] load_project_snapshot_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform : @semantic.TargetPlatform,
  environment : ArrayView[(String, String)],
) -> @project.ProjectSnapshot raise ApplicationError {
  let request = project_load_request(arguments, context, platform, environment)
  @project.load_snapshot(
    host,
    request,
    allow_unstable=arguments.flag("unstable"),
  ) catch {
    Load(error) => raise Load(error)
    Path(error) => raise Path(error)
    WorkingDirectory(error) => raise WorkingDirectory(error)
    Semantic(error) => raise Semantic(error)
    Compilation(error) => raise Project(error)
  }
}
