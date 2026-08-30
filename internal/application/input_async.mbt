///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[T : @host.HostFs + @host.HostSourceReader] load_input_with_directories_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> (@loader.LoadedSource, @workdir.WorkingDirectoryModel) raise ApplicationError {
  if arguments.flag("global-justfile") {
    let (path, directories) = global_input_directories(context)
    let loaded = @loader.load_async(host, path, context.source_id()) catch {
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
      let loaded = @loader.load_async(host, resolved, context.source_id()) catch {
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
      let loaded = @loader.load_async(host, path, context.source_id()) catch {
        error => raise Load(error)
      }
      (loaded, directories)
    }
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[T : @host.HostFs + @host.HostSourceReader] load_input_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @loader.LoadedSource raise ApplicationError {
  load_input_with_directories_async(host, arguments, context).0
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[T : @host.HostFs + @host.HostSourceReader] load_graph_input_with_directories_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform? : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
  environment? : ArrayView[(String, String)] = [],
) -> (@loader.LoadedGraph, @workdir.WorkingDirectoryModel) raise ApplicationError {
  if arguments.flag("global-justfile") {
    let (path, directories) = global_input_directories(context)
    let graph = @loader.load_graph_async(
      host,
      path,
      context.source_id(),
      platform~,
      environment~,
    ) catch {
      error => raise Load(error)
    }
    return (graph, directories)
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
      let graph = @loader.load_stdin_graph_async(
        host,
        context.stdin().to_owned(),
        context.source_id(),
        directories.project_directory(),
        platform~,
        environment~,
      ) catch {
        error => raise Load(error)
      }
      (graph, directories)
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
      let graph = @loader.load_graph_async(
        host,
        resolved,
        context.source_id(),
        platform~,
        environment~,
      ) catch {
        error => raise Load(error)
      }
      (graph, directories)
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
      let graph = @loader.load_graph_async(
        host,
        path,
        context.source_id(),
        platform~,
        environment~,
      ) catch {
        error => raise Load(error)
      }
      (graph, directories)
    }
  }
}

///|
/// Keep asynchronous project preparation behind the project boundary. The
/// application layer only translates CLI arguments into a load request and
/// maps the project-owned errors into its response vocabulary.
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[T : @host.HostFs + @host.HostSourceReader] load_project_snapshot_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform : @semantic.TargetPlatform,
  environment : ArrayView[(String, String)],
) -> @project.ProjectSnapshot raise ApplicationError {
  let request = project_load_request(arguments, context, platform, environment)
  @project.load_snapshot_async(
    host,
    request,
    allow_unstable=arguments.flag("unstable"),
  ) catch {
    @project.Load(error) => raise Load(error)
    @project.Path(error) => raise Path(error)
    @project.WorkingDirectory(error) => raise WorkingDirectory(error)
    @project.Semantic(error) => raise Semantic(error)
    @project.Compilation(error) => raise Project(error)
  }
}

///|
#cfg(target="native")
fn[T : @host.HostFs] load_project_snapshot_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform : @semantic.TargetPlatform,
  environment : ArrayView[(String, String)],
) -> @project.ProjectSnapshot raise ApplicationError {
  load_project_snapshot(host, arguments, context, platform, environment)
}

///|
#cfg(target="native")
fn[T : @host.HostFs] load_input_with_directories_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> (@loader.LoadedSource, @workdir.WorkingDirectoryModel) raise ApplicationError {
  load_input_with_directories(host, arguments, context)
}

///|
#cfg(target="native")
fn[T : @host.HostFs] load_graph_input_with_directories_async(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform? : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
  environment? : ArrayView[(String, String)] = [],
) -> (@loader.LoadedGraph, @workdir.WorkingDirectoryModel) raise ApplicationError {
  load_graph_input_with_directories(
    host,
    arguments,
    context,
    platform~,
    environment~,
  )
}
