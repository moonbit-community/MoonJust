///|
fn format_check_response(
  source : @source.Source,
) -> @cli.ApplicationResponse raise ApplicationError {
  let result = @formatter.check(source) catch { error => raise Format(error) }
  if result.changed() {
    let diff = "-" +
      source.text().trim_end().to_owned() +
      "\n+" +
      result.formatted().trim_end().to_owned() +
      "\n"
    @cli.ApplicationResponse::new(
      @utf8.encode(diff),
      b"error: formatted justfile differs from original\n",
      1,
    )
  } else {
    @cli.ApplicationResponse::success()
  }
}

///|
fn[T : @host.HostFs + @host.HostTemp] format_response(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  let selection = input_selection(arguments, context.cwd().flavor())
  let loaded = load_input(host, arguments, context)
  let result = @formatter.check(loaded.source()) catch {
    error => raise Format(error)
  }
  match selection {
    Stdin =>
      @cli.ApplicationResponse::success(stdout=@utf8.encode(result.formatted()))
    File(_) | Search if @loader.is_markdown_path(loaded.path()) =>
      @cli.ApplicationResponse::success(stdout=@utf8.encode(result.formatted()))
    Search | File(_) => {
      if result.changed() {
        @host.write_file_atomic(
          host,
          loaded.canonical_path(),
          @utf8.encode(result.formatted()),
        ) catch {
          error => raise Host(error)
        }
      }
      @cli.ApplicationResponse::success(
        stderr=@utf8.encode(
          "wrote justfile to `\{loaded.path().as_string()}`\n",
        ),
      )
    }
  }
}

///|
const INIT_TEMPLATE : String = "# https://just.systems\n\ndefault:\n    echo 'Hello, world!'\n"

///|
fn[T : @host.HostFs + @host.HostTemp] init_response(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  if arguments.positional().length() > 1 {
    raise Query(
      "`--init` used with unexpected argument: `" +
      arguments.positional()[1] +
      "`",
    )
  }
  let path = match arguments.value("justfile") {
    Some("-") => raise Query("`--init` cannot write to standard output")
    Some(value) => {
      let path = @path.PathValue::new(value, context.cwd().flavor()) catch {
        error => raise Path(error)
      }
      if path.is_absolute() {
        path
      } else {
        context.cwd().join(path) catch {
          error => raise Path(error)
        }
      }
    }
    None => {
      let directory = match arguments.positional().get(0) {
        Some(value) => {
          let path = @path.PathValue::new(value, context.cwd().flavor()) catch {
            error => raise Path(error)
          }
          if path.is_absolute() {
            path
          } else {
            context.cwd().join(path) catch {
              error => raise Path(error)
            }
          }
        }
        None => context.cwd()
      }
      let filename = @path.PathValue::new("justfile", context.cwd().flavor()) catch {
        error => raise Path(error)
      }
      directory.join(filename) catch {
        error => raise Path(error)
      }
    }
  }
  let exists = @host.HostFs::file_exists(host, path) catch {
    error => raise Host(error)
  }
  if exists {
    raise AlreadyExists(path)
  }
  @host.write_file_atomic(
    host,
    path,
    @utf8.encode(INIT_TEMPLATE),
    overwrite=false,
  ) catch {
    error => raise Host(error)
  }
  @cli.ApplicationResponse::success(
    stderr=@utf8.encode("wrote justfile to `\{path.as_string()}`\n"),
  )
}

///|
/// Execute the Phase 6 file-oriented commands without ambient process state.
pub fn[T : @host.HostFs + @host.HostTemp] execute_file_command(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  match arguments.command() {
    CheckCommand => {
      let loaded = load_input(host, arguments, context)
      format_check_response(loaded.source())
    }
    FormatCommand => format_response(host, arguments, context)
    InitCommand => init_response(host, arguments, context)
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
}
