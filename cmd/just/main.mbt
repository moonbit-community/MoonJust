///|
fn needs_stdin(arguments : ArrayView[String]) -> Bool {
  for index, argument in arguments {
    if argument == "--justfile=-" || argument == "-f-" {
      return true
    }
    if (argument == "--justfile" || argument == "-f") &&
      arguments.get(index + 1) == Some("-") {
      return true
    }
  }
  false
}

///|
fn path_flavor(path : String) -> @path.PathFlavor {
  let values = path.to_array()
  if path.contains("\\") ||
    (
      values.length() >= 2 &&
      values[0].is_ascii_alphabetic() &&
      values[1] == ':'
    ) {
    Windows
  } else {
    Unix
  }
}

///|
fn failure(message : String, exit_code : Int) -> @cli.ApplicationResponse {
  @cli.ApplicationResponse::new(
    b"",
    @utf8.encode(message.trim_end().to_owned() + "\n"),
    exit_code,
  )
}

///|
async fn[
  F : @host.HostFs + @host.HostTemp + @host.HostAsyncScriptTemp + @host.HostCacheStore,
  E : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] run_cli(
  host : F,
  environment_host : E,
  argv : ArrayView[String],
  stdin : Bytes,
) -> @cli.ApplicationResponse {
  let arguments = try @cli.parse_arguments(argv, {}) catch {
    Invalid(message) => return failure(message, 2)
    Unsupported(name) =>
      return failure("error: option '\{name}' is not supported yet", 2)
  } noraise {
    value => value
  }
  if arguments.flag("help") {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(@cli.render_help()),
    )
  }
  if arguments.flag("version") {
    return @cli.ApplicationResponse::success(
      stdout=@utf8.encode(@moonjust.version_line() + "\n"),
    )
  }
  let cwd_text = @env.current_dir().unwrap_or(".")
  let cwd = try @path.PathValue::new(cwd_text, path_flavor(cwd_text)) catch {
    error =>
      return failure("error: invalid current directory: \{Repr(error)}", 1)
  } noraise {
    value => value
  }
  let context = @application.ApplicationContext::new(cwd, stdin~)
  if arguments.command() == RunCommand {
    let process = @host_process.ProcessAdapter::new()
    let plan = try
      @application.plan_run_command_async(
        host, environment_host, process, arguments, context,
      )
    catch {
      error => return failure(error.message(), error.exit_code())
    } noraise {
      value => value
    }
    let report = try
      @runtime.execute_plan(process, host, environment_host, plan)
    catch {
      error => {
        let stderr : Array[Byte] = []
        for byte in error.stderr() {
          stderr.push(byte)
        }
        for byte in @utf8.encode(error.message().trim_end().to_owned() + "\n") {
          stderr.push(byte)
        }
        return @cli.ApplicationResponse::new(
          error.stdout().to_owned(),
          Bytes::from_array(stderr),
          error.exit_code(),
        )
      }
    } noraise {
      value => value
    }
    @cli.ApplicationResponse::new(
      report.stdout().to_owned(),
      report.stderr().to_owned(),
      0,
    )
  } else if arguments.command() == CleanCommand {
    try @application.execute_clean_command(host, arguments, context) catch {
      error => failure(error.message(), error.exit_code())
    } noraise {
      response => response
    }
  } else {
    try @application.execute_command(host, arguments, context) catch {
      error => failure(error.message(), error.exit_code())
    } noraise {
      response => response
    }
  }
}

///|
async fn emit_response(response : @cli.ApplicationResponse) -> Unit {
  if !response.stdout().is_empty() {
    @stdio.stdout.write(response.stdout())
  }
  if !response.stderr().is_empty() {
    @stdio.stderr.write(response.stderr())
  }
  runtime_exit(response.exit_code())
}

///|
async fn main {
  let raw_argv = @env.args()
  let argv = raw_argv[1:]
  let stdin = if needs_stdin(argv) {
    @stdio.stdin.read_all().binary() catch {
      _ => b""
    }
  } else {
    b""
  }
  emit_response(
    run_cli(runtime_host(), runtime_environment_host(), argv, stdin),
  ) catch {
    _ => runtime_exit(1)
  }
}
