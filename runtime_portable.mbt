///|
fn runtime_host() -> @host_wasm.ExecutionFs {
  @host_wasm.ExecutionFs::new()
}

///|
fn runtime_environment_host() -> @host_wasm.PortableHost {
  @host_wasm.PortableHost::new()
}

///|
#cfg(target="wasm")
fn portable_exit(code : Int) -> Unit = "wasi_snapshot_preview1" "proc_exit"

///|
#cfg(any(target="wasm-gc", target="js"))
fn portable_exit(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

///|
fn runtime_exit(code : Int) -> Unit {
  if code != 0 {
    portable_exit(code)
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
priv struct SyncFileInvocation {
  filesystem : @host_wasm.ReadOnlyFs
  environment_host : @host_wasm.PortableHost
  arguments : @cli.CliArguments
  context : @project.ProjectInput
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn prepare_sync_file_invocation(
  argv : ArrayView[String],
  expected : @cli.CommandKind,
) -> SyncFileInvocation? {
  let environment_host = @host_wasm.PortableHost::new()
  let environment = try @application.parse_environment(environment_host) catch {
    _ => return None
  } noraise {
    value => value
  }
  let arguments = try @cli.parse_arguments(argv, environment.values()) catch {
    _ => return None
  } noraise {
    value => value
  }
  guard arguments.command() == expected else { return None }
  let selected = match arguments.value("justfile") {
    Some(value) if value != "-" => value
    _ => return None
  }
  guard !arguments.flag("global-justfile") else { return None }
  guard arguments.value("working-directory") is None else { return None }
  let filesystem = @host_wasm.ReadOnlyFs::new()
  let cwd = try @host.HostEnv::current_dir(environment_host) catch {
    _ => return None
  } noraise {
    value => value
  }
  let selected_path = try @path.PathValue::new(selected, cwd.flavor()) catch {
    _ => return None
  } noraise {
    value => value
  }
  let selected_path = if selected_path.is_absolute() {
    selected_path
  } else {
    try cwd.join(selected_path) catch {
      _ => return None
    } noraise {
      value => value
    }
  }
  let metadata = try @host.HostFs::metadata(filesystem, selected_path) catch {
    _ => return None
  } noraise {
    value => value
  }
  guard metadata.is_file() else { return None }
  guard metadata.size() <=
    @lexer.LexerLimits::default().max_source_bytes().to_int64() else {
    return None
  }
  let context = @project.ProjectInput::new(cwd)
  let context = try
    @application.resolve_global_context(
      filesystem, environment_host, arguments, context,
    )
  catch {
    _ => return None
  } noraise {
    value => value
  }
  Some({ filesystem, environment_host, arguments, context, })
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn try_sync_file_command(
  argv : ArrayView[String],
  expected : @cli.CommandKind,
) -> Bool {
  guard prepare_sync_file_invocation(argv, expected) is Some(prepared) else {
    return false
  }
  let response = try
    @application.execute_file_command(
      prepared.filesystem,
      prepared.arguments,
      prepared.context,
    )
  catch {
    _ => return false
  } noraise {
    value => value
  }
  response.exit_code() == 0 &&
  response.stdout().is_empty() &&
  response.stderr().is_empty()
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn try_sync_summary(argv : ArrayView[String]) -> String? {
  guard prepare_sync_file_invocation(argv, SummaryCommand) is Some(prepared) else {
    return None
  }
  let response = try
    @application.execute_query_command(
      prepared.environment_host,
      prepared.arguments,
      prepared.context,
    )
  catch {
    _ => return None
  } noraise {
    value => value
  }
  guard response.exit_code() == 0 && response.stderr().is_empty() else {
    return None
  }
  let text = @utf8.decode(response.stdout()) catch { _ => return None }
  guard text.has_suffix("\n") && text != "\n" else { return None }
  Some(text[:text.length() - 1].to_owned())
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
fn sync_file_command_hint(argv : ArrayView[String]) -> Int {
  let mut check = false
  let mut format = false
  for argument in argv {
    if argument == "--summary" {
      return 1
    }
    if argument == "--check" {
      check = true
    } else if argument == "--fmt" {
      format = true
    }
  }
  if check {
    2
  } else if format {
    3
  } else {
    0
  }
}
