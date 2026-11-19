///|
fn diff_lines(text : String) -> Array[StringView] {
  let lines = []
  let mut start = 0
  for i = 0; i < text.length(); i = i + 1 {
    if text[i] == '\n' {
      lines.push(text[start:i + 1])
      start = i + 1
    }
  }
  if start < text.length() {
    lines.push(text[start:])
  }
  lines
}

///|
fn format_diff(original : String, formatted : String, color : Bool) -> String {
  let left = diff_lines(original)
  let right = diff_lines(formatted)
  let diff = @diff.Diff(old=left, new=right, algorithm=Patience)
  let output = StringBuilder()
  for edit in diff.edits() {
    let (lines, prefix, paint) = match edit {
      Equal(old_index~, len~, ..) => (left[old_index:old_index + len], " ", "")
      Delete(old_index~, old_len~, ..) =>
        (left[old_index:old_index + old_len], "-", "\u{001b}[31m")
      Insert(new_index~, new_len~, ..) =>
        (right[new_index:new_index + new_len], "+", "\u{001b}[32m")
    }
    for line in lines {
      if color {
        output.write_string(paint)
      }
      output.write_string(prefix)
      output.write_stringview(line)
      if !line.has_suffix("\n") {
        output.write_char('\n')
      }
      if color && paint != "" {
        output.write_string("\u{001b}[0m")
      }
    }
  }
  output.to_string()
}

///|
async fn[H : @host.HostTerminal] format_check_response(
  terminal : H,
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
    let color = selected_color_active(terminal, arguments, Stdout)
    let diff = format_diff(loaded.source().text(), formatted, color)
    let stderr = if selected_color_active(terminal, arguments, Stderr) {
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
async fn[T : @host.HostFs + @host.HostAtomicFs] format_response(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
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
async fn[T : @host.HostFs + @host.HostAtomicFs] init_response(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
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
pub async fn[T : @host.HostFs + @host.HostAtomicFs, H : @host.HostTerminal] execute_file_command(
  host : T,
  terminal : H,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  match arguments.command() {
    CheckCommand => {
      let loaded = load_input(host, arguments, context)
      perf_detail_mark("file.load")
      let response = format_check_response(terminal, loaded, arguments)
      perf_detail_mark("file.format")
      ignore(perf_detail_emit() catch { _ => () })
      response
    }
    FormatCommand => {
      let response = format_response(host, arguments, context)
      perf_detail_mark("file.format")
      ignore(perf_detail_emit() catch { _ => () })
      response
    }
    InitCommand => init_response(host, arguments, context)
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
}
