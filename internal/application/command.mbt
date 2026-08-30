///|
fn command_export_environment(
  project : @semantic.ProjectCompilation,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
) -> @evaluator.Environment raise ApplicationError {
  let lazy_environment = @evaluator.LazyEnvironment::new(compilation)
  let overrides = project_variable_overrides(
    project,
    @modulepath.ModulePath::root(),
    arguments,
  )
  lazy_environment.apply_overrides(overrides) catch {
    error => raise Evaluation(error)
  }
  for name in compilation.variable_names() {
    guard compilation.variable(name) is Some(assignment) else { continue }
    if assignment.exported() || compilation.settings().bool("export") {
      ignore(
        lazy_environment.resolve(name) catch {
          error => raise Evaluation(error)
        },
      )
    }
  }
  lazy_environment.environment()
}

///|
fn command_display(arguments : ArrayView[String]) -> String {
  arguments.map(fn(argument) { "`" + argument + "`" }).join(" ")
}

///|
/// Execute `--command` with the selected project directory, dotenv entries,
/// overrides, and exported assignments. Child streams remain live.
#warnings("-unused_trait_bound")
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
  P : @host.HostAsyncProcess,
  H : @host.HostEnv,
] execute_command_command_async(
  filesystem : F,
  effects : H,
  process : P,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  if arguments.command() != CommandCommand {
    raise UnsupportedCommand("arbitrary execution for non-command mode")
  }
  guard arguments.positional().get(0) is Some(binary) else {
    raise Query(
      "a value is required for '--command <COMMAND>...' but none was supplied\n\nFor more information, try '--help'.",
    )
  }
  let loading_environment = @host.HostEnv::env_entries(effects) catch {
    error => raise Host(error)
  }
  let snapshot = load_project_snapshot_async(
    filesystem,
    arguments,
    context,
    @semantic.TargetPlatform::new(Other("unknown"), false),
    loading_environment,
  )
  let directories = snapshot.directories()
  let project = snapshot.compilation()
  validate_project_variable_overrides(project, arguments)
  let compilation = project.root()
  let global = command_export_environment(project, compilation, arguments)
  let root = @modulepath.ModulePath::root()
  let cwd = project_module_cwd(
    project,
    directories,
    root,
    evaluated_string_setting(compilation, global, "working-directory"),
    compilation.settings().bool("no-cd"),
  )
  let environment = compose_dotenv_environment(
    filesystem,
    compilation,
    arguments,
    global,
    cwd,
    process_environment(loading_environment, global, cwd.flavor()),
  )
  let (program, child_arguments) = if arguments.flag("shell-command") {
    let shell = selected_shell(compilation, global, arguments, cwd.flavor())
    let shell_arguments = shell.arguments().to_owned()
    shell_arguments.push(arguments.positional().join(" "))
    (shell.program(), shell_arguments)
  } else {
    (binary, arguments.positional()[1:].to_owned())
  }
  let spec = @host.CommandSpec::new(program, child_arguments) catch {
    error => raise Host(error)
  }
  spec.set_cwd(cwd)
  spec.set_inherit_environment(false)
  for entry in environment {
    spec.add_environment(entry.0, entry.1) catch {
      error => raise Host(error)
    }
  }
  spec.set_inherit_stdin(true)
  let output : @host.StdioBehavior = if arguments.flag("quiet") {
    Discard
  } else {
    Inherit
  }
  spec.set_stdout(output)
  spec.set_stderr(output)
  let display = command_display(arguments.positional())
  let result = @host.HostAsyncProcess::run_process_async(process, spec) catch {
    error => raise interactive_invocation_failure("command", display, error)
  }
  match result.termination() {
    Exited(0) => @cli.ApplicationResponse::success()
    termination => raise interactive_failure("command", display, termination)
  }
}
