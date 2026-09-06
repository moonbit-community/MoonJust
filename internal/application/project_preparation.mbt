///|
fn input_selection(
  arguments : @cli.CliArguments,
  flavor : @path.PathFlavor,
) -> @cli.InputSelection raise ApplicationError {
  match arguments.value("justfile") {
    None => Search
    Some("-") => Stdin
    Some(value) =>
      File(
        @path.PathValue::new(value, flavor) catch {
          error => raise Path(error)
        },
      )
  }
}

///|
fn working_directory_argument(
  arguments : @cli.CliArguments,
  flavor : @path.PathFlavor,
) -> @path.PathValue? raise ApplicationError {
  match arguments.value("working-directory") {
    None => None
    Some(value) =>
      Some(
        @path.PathValue::new(value, flavor) catch {
          error => raise Path(error)
        },
      )
  }
}

///|
fn ceiling_argument(
  arguments : @cli.CliArguments,
  cwd : @path.PathValue,
) -> @path.PathValue? raise ApplicationError {
  match arguments.value("ceiling") {
    None => None
    Some(value) => {
      let path = @path.PathValue::new(value, cwd.flavor()) catch {
        error => raise Path(error)
      }
      Some(cwd.join(path) catch { error => raise Path(error) })
    }
  }
}

///|
fn global_input_directories(
  context : @project.ProjectInput,
) -> (@path.PathValue, @workdir.WorkingDirectoryModel) raise ApplicationError {
  guard context.global_justfile() is Some(path) else {
    raise Query("global justfile context was not resolved")
  }
  guard context.global_project_directory() is Some(project) else {
    raise Query("global justfile project directory was not resolved")
  }
  let directories = @workdir.WorkingDirectoryModel::from_global_justfile(
    context.cwd(),
    path,
    project,
  ) catch {
    error => raise WorkingDirectory(error)
  }
  (path, directories)
}

///|
fn search_prefixed_invocation(
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> (@cli.CliArguments, @project.ProjectInput) raise ApplicationError {
  let path_prefixed = !arguments.positional().is_empty() &&
    ({
      let first = arguments.positional()[0]
      first == "." ||
      first == ".." ||
      first.contains("/") ||
      first.contains("\\")
    })
  if path_prefixed &&
    (
      arguments.flag("global-justfile") ||
      arguments.value("justfile") is Some(_) ||
      arguments.value("working-directory") is Some(_)
    ) {
    raise Query(
      "path-prefixed recipes may not be used with `--global-justfile`, " +
      "`--working-directory`, or `--justfile`",
    )
  }
  if arguments.command() != RunCommand ||
    arguments.flag("global-justfile") ||
    arguments.value("justfile") is Some(_) ||
    arguments.positional().is_empty() {
    return (arguments, context)
  }
  let requested = arguments.positional()[0]
  if requested != "." &&
    requested != ".." &&
    !requested.contains("/") &&
    !requested.contains("\\") {
    return (arguments, context)
  }
  // just treats the first path-like positional as a search directory. A
  // trailing separator means that no recipe name was supplied; PathValue
  // normalizes separators, so preserve that distinction before parsing it.
  let trailing_separator = requested.has_suffix("/") ||
    requested.has_suffix("\\")
  let (directory_text, recipe) = if requested == "." || requested == ".." {
    (requested, None)
  } else if trailing_separator {
    (requested, None)
  } else {
    let separator = match (requested.rev_find("/"), requested.rev_find("\\")) {
      (Some(left), Some(right)) => Some(if left > right { left } else { right })
      (Some(index), None) => Some(index)
      (None, Some(index)) => Some(index)
      (None, None) => None
    }
    match separator {
      Some(index) => {
        let directory = requested[:index + 1].to_owned()
        let recipe = requested[index + 1:].to_owned()
        if recipe.is_empty() {
          (requested, None)
        } else {
          (directory, Some(recipe))
        }
      }
      None => return (arguments, context)
    }
  }
  let directory = @path.PathValue::new(directory_text, context.cwd().flavor()) catch {
    error => raise Path(error)
  }
  let cwd = context.cwd().join(directory) catch { error => raise Path(error) }
  let positional : Array[String] = []
  match recipe {
    Some(name) => positional.push(name)
    None => ()
  }
  for argument in arguments.positional()[1:] {
    positional.push(argument)
  }
  (arguments.with_run_positionals(positional), context.with_cwd(cwd))
}

///|
fn[F : @host.HostFs] query_search_prefix(
  host : F,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> (@cli.CliArguments, @project.ProjectInput) raise ApplicationError {
  if arguments.flag("global-justfile") ||
    arguments.value("justfile") is Some(_) ||
    arguments.value("working-directory") is Some(_) ||
    arguments.positional().is_empty() {
    return (arguments, context)
  }
  let positional = arguments.positional().to_owned()
  let mut directory_text : String? = None
  let mut remaining = positional.copy()
  let first = positional[0]
  // A module-qualified recipe is a semantic name, never a filesystem path.
  // Avoid probing it through HostFs: MoonX inspect policy correctly rejects
  // that read, but the query path should proceed to module resolution.
  if first.contains("::") {
    return (arguments, context)
  }
  let first_path = @path.PathValue::new(first, context.cwd().flavor()) catch {
    error => raise Path(error)
  }
  let first_full = context.cwd().join(first_path) catch {
      error => raise Path(error)
    }
  let first_is_directory = try @host.HostFs::metadata(host, first_full) catch {
    _ => false
  } noraise {
    metadata => metadata.is_directory()
  }
  if first_is_directory {
    directory_text = Some(first)
    ignore(remaining.remove(0))
  } else if (
      arguments.command() == ShowCommand || arguments.command() == UsageCommand
    ) &&
    positional.length() == 1 &&
    (first.contains("/") || first.contains("\\")) {
    guard first_path.file_name() is Some(name) else {
      return (arguments, context)
    }
    guard first_path.parent() is Some(parent) else {
      return (arguments, context)
    }
    directory_text = Some(parent.as_string())
    remaining = [name]
  }
  match directory_text {
    None => (arguments, context)
    Some(directory) => {
      let path = @path.PathValue::new(directory, context.cwd().flavor()) catch {
        error => raise Path(error)
      }
      let cwd = context.cwd().join(path) catch { error => raise Path(error) }
      (arguments.with_positionals(remaining), context.with_cwd(cwd))
    }
  }
}

///|
fn[T : @host.HostFs] load_input_with_directories(
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
fn[T : @host.HostFs] load_input(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @loader.LoadedSource raise ApplicationError {
  load_input_with_directories(host, arguments, context).0
}

///|
fn[T : @host.HostFs] load_graph_input_with_directories(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform? : @semantic.TargetPlatform = @semantic.TargetPlatform::new(
    Other("unknown"),
    false,
  ),
  environment? : ArrayView[(String, String)] = [],
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
/// Build the package-neutral project request once at the application boundary.
/// Project loading itself does not depend on CLI argument representation.
fn project_load_request(
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  platform : @semantic.TargetPlatform,
  environment : ArrayView[(String, String)],
) -> @project.ProjectLoadRequest raise ApplicationError {
  let selection = match input_selection(arguments, context.cwd().flavor()) {
    Search => @project.SourceSelection::Search
    Stdin => Stdin
    File(path) => File(path)
  }
  let working_directory = working_directory_argument(
    arguments,
    context.cwd().flavor(),
  )
  let ceiling = ceiling_argument(arguments, context.cwd())
  @project.ProjectLoadRequest::new(
    context,
    selection,
    arguments.value("justfile-name").unwrap_or("justfile"),
    platform,
    environment,
    working_directory?,
    ceiling?,
  )
}

///|
#cfg(target="native")
fn[T : @host.HostFs] load_project_snapshot(
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
