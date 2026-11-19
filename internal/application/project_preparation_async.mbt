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
async fn[T : @host.HostFs] load_project_sources(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform~ : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
  environment~ : ArrayView[(String, String)] = [],
) -> @project.ProjectSources raise ApplicationError {
  let request = project_load_request(arguments, context, platform, environment)
  @project.load_sources(host, request) catch {
    error =>
      raise AtProject(
        ApplicationError::from_project_error(error),
        None,
        context.cwd(),
      )
  }
}

///|
fn ApplicationError::from_project_error(
  error : @project.ProjectError,
) -> ApplicationError {
  match error {
    Load(error) => Load(error)
    Path(error) => Path(error)
    WorkingDirectory(error) => WorkingDirectory(error)
    Semantic(error) => Semantic(error)
    Compilation(error) => Project(error)
  }
}

///|
/// Keep asynchronous project preparation behind the project boundary. The
/// application layer only translates CLI arguments into a load request and
/// maps the project-owned errors into its response vocabulary.
async fn[T : @host.HostFs] load_project_snapshot(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform : @semantic.TargetPlatform,
  environment : ArrayView[(String, String)],
) -> @project.ProjectSnapshot raise ApplicationError {
  let sources = load_project_sources(
    host,
    arguments,
    context,
    platform~,
    environment~,
  )
  sources.compile(allow_unstable=arguments.flag("unstable"), platform~) catch {
    error =>
      raise ApplicationError::from_project_error(error).with_project_sources(
        sources.graph(),
        context.cwd(),
      )
  }
}
