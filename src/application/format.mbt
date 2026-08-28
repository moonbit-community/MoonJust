///|
fn format_diff(original : String, formatted : String, color : Bool) -> String {
  let left : Array[String] = original
    .trim_end()
    .split("\n")
    .map(fn(line) { line.to_owned() })
    .collect()
  let right : Array[String] = formatted
    .trim_end()
    .split("\n")
    .map(fn(line) { line.to_owned() })
    .collect()
  let builder = StringBuilder()
  let length = Int::max(left.length(), right.length())
  for index in 0..<length {
    match (left.get(index), right.get(index)) {
      (Some(before), Some(after)) if before == after =>
        builder.write_string(" " + before + "\n")
      (Some(before), Some(after)) =>
        if color {
          builder.write_string("\u{001b}[31m-" + before + "\n\u{001b}[0m")
          builder.write_string("\u{001b}[32m+" + after + "\n\u{001b}[0m")
        } else {
          builder.write_string("-" + before + "\n+" + after + "\n")
        }
      (Some(before), None) => builder.write_string("-" + before + "\n")
      (None, Some(after)) => builder.write_string("+" + after + "\n")
      (None, None) => ()
    }
  }
  builder.to_string()
}

///|
fn format_check_response(
  loaded : @loader.LoadedSource,
  arguments : @cli.CliArguments,
) -> @cli.ApplicationResponse raise ApplicationError {
  let indentation = formatting_indentation(arguments, loaded.ast())
  let formatted = @formatter.format_with_indentation(loaded.ast(), indentation) catch {
    error => raise Format(error)
  }
  if formatted != loaded.source().text() {
    if arguments.flag("quiet") {
      return @cli.ApplicationResponse::new(b"", b"", 1)
    }
    let color = arguments.value("color") == Some("always")
    let diff = format_diff(loaded.source().text(), formatted, color)
    let stderr = if color {
      "\u{001b}[1;31merror\u{001b}[0m: \u{001b}[1mformatted justfile differs from original\u{001b}[0m\n"
    } else {
      "error: formatted justfile differs from original\n"
    }
    @cli.ApplicationResponse::new(@utf8.encode(diff), @utf8.encode(stderr), 1)
  } else {
    @cli.ApplicationResponse::success()
  }
}

///|
fn write_permission_detail(path : @path.PathValue) -> String {
  if path.flavor() == Windows {
    "Access is denied. (os error 5)"
  } else {
    "Permission denied (os error 13)"
  }
}

///|
fn write_directory_detail(path : @path.PathValue) -> String {
  if path.flavor() == Windows {
    "Access is denied. (os error 5)"
  } else {
    "Is a directory (os error 21)"
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
  let indentation = formatting_indentation(arguments, loaded.ast())
  let formatted = @formatter.format_with_indentation(loaded.ast(), indentation) catch {
    error => raise Format(error)
  }
  match selection {
    Stdin => @cli.ApplicationResponse::success(stdout=@utf8.encode(formatted))
    File(_) | Search if @loader.is_markdown_path(loaded.path()) =>
      @cli.ApplicationResponse::success(stdout=@utf8.encode(formatted))
    Search | File(_) => {
      if formatted != loaded.source().text() {
        @host.write_file_atomic(
          host,
          loaded.canonical_path(),
          @utf8.encode(formatted),
        ) catch {
          PermissionDenied(_, detail=_) =>
            raise WriteJustfile(
              path=loaded.path(),
              detail=write_permission_detail(loaded.path()),
            )
          error => raise Host(error)
        }
        return @cli.ApplicationResponse::success(
          stderr=@utf8.encode(
            "wrote justfile to `\{loaded.path().as_string()}`\n",
          ),
        )
      }
      @cli.ApplicationResponse::success()
    }
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[T : @host.HostFs + @host.HostSourceReader + @host.HostAtomicFs] format_response_async(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  let selection = input_selection(arguments, context.cwd().flavor())
  let loaded = load_input_async(host, arguments, context)
  let indentation = formatting_indentation(arguments, loaded.ast())
  let formatted = @formatter.format_with_indentation(loaded.ast(), indentation) catch {
    error => raise Format(error)
  }
  match selection {
    Stdin => @cli.ApplicationResponse::success(stdout=@utf8.encode(formatted))
    File(_) | Search if @loader.is_markdown_path(loaded.path()) =>
      @cli.ApplicationResponse::success(stdout=@utf8.encode(formatted))
    Search | File(_) => {
      if formatted != loaded.source().text() {
        @host.HostAtomicFs::write_file_atomic(
          host,
          loaded.canonical_path(),
          @utf8.encode(formatted),
          true,
        ) catch {
          PermissionDenied(_, detail=_) =>
            raise WriteJustfile(
              path=loaded.path(),
              detail=write_permission_detail(loaded.path()),
            )
          error => raise Host(error)
        }
        return @cli.ApplicationResponse::success(
          stderr=@utf8.encode(
            "wrote justfile to `\{loaded.path().as_string()}`\n",
          ),
        )
      }
      @cli.ApplicationResponse::success()
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
    Some("-") =>
      raise Query("cannot use justfile from standard input with `--init`")
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
        None =>
          global_project_root(
            host,
            context.cwd(),
            ceiling_argument(arguments, context.cwd()),
          )
      }
      let filename = @path.PathValue::new(
        arguments.value("justfile-name").unwrap_or("justfile"),
        context.cwd().flavor(),
      ) catch {
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
    let metadata = @host.HostFs::metadata(host, path) catch {
      error => raise Host(error)
    }
    if metadata.is_directory() {
      raise WriteJustfile(path~, detail=write_directory_detail(path))
    }
    raise AlreadyExists(path)
  }
  @host.write_file_atomic(
    host,
    path,
    @utf8.encode(INIT_TEMPLATE),
    overwrite=false,
  ) catch {
    PermissionDenied(_, detail=_) =>
      raise WriteJustfile(path~, detail=write_permission_detail(path))
    error => raise Host(error)
  }
  @cli.ApplicationResponse::success(
    stderr=@utf8.encode("wrote justfile to `\{path.as_string()}`\n"),
  )
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
async fn[T : @host.HostFs + @host.HostAtomicFs] init_response_async(
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
    Some("-") =>
      raise Query("cannot use justfile from standard input with `--init`")
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
        None =>
          global_project_root(
            host,
            context.cwd(),
            ceiling_argument(arguments, context.cwd()),
          )
      }
      let filename = @path.PathValue::new(
        arguments.value("justfile-name").unwrap_or("justfile"),
        context.cwd().flavor(),
      ) catch {
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
    let metadata = @host.HostFs::metadata(host, path) catch {
      error => raise Host(error)
    }
    if metadata.is_directory() {
      raise WriteJustfile(path~, detail=write_directory_detail(path))
    }
    raise AlreadyExists(path)
  }
  @host.HostAtomicFs::write_file_atomic(
    host,
    path,
    @utf8.encode(INIT_TEMPLATE),
    false,
  ) catch {
    PermissionDenied(_, detail=_) =>
      raise WriteJustfile(path~, detail=write_permission_detail(path))
    error => raise Host(error)
  }
  @cli.ApplicationResponse::success(
    stderr=@utf8.encode("wrote justfile to `\{path.as_string()}`\n"),
  )
}

///|
/// Execute the file-oriented commands without ambient process state.
pub fn[T : @host.HostFs + @host.HostTemp] execute_file_command(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  match arguments.command() {
    CheckCommand => {
      let loaded = load_input(host, arguments, context)
      format_check_response(loaded, arguments)
    }
    FormatCommand => format_response(host, arguments, context)
    InitCommand => init_response(host, arguments, context)
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
}

///|
/// Async file-command entry point for policy-aware native and wasm CLI hosts.
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn[T : @host.HostFs + @host.HostSourceReader + @host.HostAtomicFs] execute_file_command_async(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  match arguments.command() {
    CheckCommand => {
      let loaded = load_input_async(host, arguments, context)
      perf_detail_mark("file.load")
      let response = format_check_response(loaded, arguments)
      perf_detail_mark("file.format")
      ignore(perf_detail_emit() catch { _ => () })
      response
    }
    FormatCommand => {
      let response = format_response_async(host, arguments, context)
      perf_detail_mark("file.format")
      ignore(perf_detail_emit() catch { _ => () })
      response
    }
    InitCommand => init_response_async(host, arguments, context)
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
}

///|
/// Native file commands reuse the synchronous application path. Keeping the
/// async API at this boundary preserves the CLI dispatcher while removing the
/// native-only I/O state machines.
#cfg(target="native")
#warnings("-unused_async")
pub async fn[T : @host.HostFs + @host.HostTemp] execute_file_command_async(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  execute_file_command(host, arguments, context)
}
