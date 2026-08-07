///|
fn format_check_response(
  source : @source.Source,
) -> @cli.ApplicationResponse raise ApplicationError {
  let result = @formatter.check(source) catch { error => raise Format(error) }
  if result.changed() {
    let output = "-" +
      source.text().trim_end().to_owned() +
      "\n+" +
      result.formatted().trim_end().to_owned() +
      "\nerror: formatted justfile differs from original\n"
    @cli.ApplicationResponse::new(@utf8.encode(output), b"", 1)
  } else {
    @cli.ApplicationResponse::success()
  }
}

///|
fn[T : @host.HostFs] format_response(
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
    Search | File(_) => {
      if result.changed() {
        @host.HostFs::write_file(
          host,
          loaded.path(),
          @utf8.encode(result.formatted()),
        ) catch {
          error => raise Host(error)
        }
      }
      @cli.ApplicationResponse::success(
        stdout=@utf8.encode(
          "wrote justfile to '\{loaded.path().as_string()}'\n",
        ),
      )
    }
  }
}

///|
const INIT_TEMPLATE : String = "# https://just.systems\n\ndefault:\n    echo 'Hello, world!'\n"

///|
fn[T : @host.HostFs] init_response(
  host : T,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  let filename = @path.PathValue::new("justfile", context.cwd().flavor()) catch {
    error => raise Path(error)
  }
  let path = context.cwd().join(filename) catch { error => raise Path(error) }
  let exists = @host.HostFs::file_exists(host, path) catch {
    error => raise Host(error)
  }
  if exists {
    raise AlreadyExists(path)
  }
  @host.HostFs::write_file(host, path, @utf8.encode(INIT_TEMPLATE)) catch {
    error => raise Host(error)
  }
  @cli.ApplicationResponse::success(
    stdout=@utf8.encode("wrote justfile to '\{path.as_string()}'\n"),
  )
}

///|
/// Execute the Phase 6 file-oriented commands without ambient process state.
pub fn[T : @host.HostFs] execute_file_command(
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
    InitCommand => init_response(host, context)
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
}
