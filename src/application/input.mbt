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
fn[T : @host.HostFs] load_input(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @loader.LoadedSource raise ApplicationError {
  match input_selection(arguments, context.cwd().flavor()) {
    Stdin =>
      @loader.load_stdin(context.stdin().to_owned(), context.source_id()) catch {
        error => raise Load(error)
      }
    File(path) =>
      @loader.load(host, path, context.source_id()) catch {
        error => raise Load(error)
      }
    Search => {
      let path = @loader.discover(host, context.cwd()) catch {
        error => raise Load(error)
      }
      @loader.load(host, path, context.source_id()) catch {
        error => raise Load(error)
      }
    }
  }
}
