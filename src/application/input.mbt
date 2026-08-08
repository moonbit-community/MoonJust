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
fn[T : @host.HostFs] load_input_with_directories(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> (@loader.LoadedSource, @workdir.WorkingDirectoryModel) raise ApplicationError {
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
      let path = @loader.discover(host, context.cwd()) catch {
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
  context : ApplicationContext,
) -> @loader.LoadedSource raise ApplicationError {
  load_input_with_directories(host, arguments, context).0
}
