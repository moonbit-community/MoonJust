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
      Some(path)
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
  guard arguments.command() != CommandCommand &&
    arguments.positional().get(0) is Some(first) else {
    return (arguments, context)
  }
  let (directory_text, recipe) = if first == "." || first == ".." {
    (first, None)
  } else if first.rev_find("/") is Some(index) {
    let name = first[index + 1:]
    (
      first[:index + 1].to_owned(),
      if name.is_empty() {
        None
      } else {
        Some(name.to_owned())
      },
    )
  } else {
    return (arguments, context)
  }
  if arguments.flag("global-justfile") ||
    arguments.value("justfile") is Some(_) ||
    arguments.value("working-directory") is Some(_) {
    raise Query(
      "path-prefixed recipes may not be used with `--global-justfile`, " +
      "`--working-directory`, or `--justfile`",
    )
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
  (arguments.with_positionals(positional), context.with_cwd(cwd))
}

///|
fn query_search_prefix(
  _host : &@host.HostFs,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> (@cli.CliArguments, @project.ProjectInput) raise ApplicationError {
  search_prefixed_invocation(arguments, context)
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
  let ceiling = ceiling_argument(arguments, context.invocation_directory())
  @project.ProjectLoadRequest::new(
    context,
    selection,
    arguments.values("justfile-name"),
    platform,
    environment,
    working_directory?,
    ceiling?,
  )
}
