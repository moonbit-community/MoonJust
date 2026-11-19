///|
fn prepare_module_runtimes(
  project : @semantic.ProjectCompilation,
  directories : @workdir.WorkingDirectoryModel,
  arguments : @cli.CliArguments,
  platform : @host.PlatformInfo,
  loading_environment : ArrayView[(String, String)],
  invocation_directory : @path.PathValue,
  globals : Map[@modulepath.ModulePath, @evaluator.Environment],
  dotenv_by_module : Map[@modulepath.ModulePath, Array[(String, String)]],
) -> Map[@modulepath.ModulePath, @planner.ProjectModuleRuntime] raise ApplicationError {
  let runtimes : Map[@modulepath.ModulePath, @planner.ProjectModuleRuntime] = Map([],
  )
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    let global = globals[path]
    let module_setting = evaluated_string_setting(
      compilation, global, "working-directory",
    )
    let evaluation_cwd = project_module_cwd(
      project, directories, path, module_setting, false,
    )
    let cwd = if compilation.settings().bool("no-cd") {
      directories.invocation_directory()
    } else {
      evaluation_cwd
    }
    let shell = selected_shell(
      compilation,
      global,
      arguments,
      evaluation_cwd.flavor(),
    )
    let base = merge_dotenv_entries(
      loading_environment.to_owned(),
      dotenv_by_module[path],
      compilation.settings().bool("dotenv-override"),
    )
    let environment = process_environment(
      base,
      global,
      evaluation_cwd.flavor(),
      unexports=compilation.unexports(),
    )
    let evaluation_context = project_evaluation_context(
      project,
      path,
      evaluation_cwd,
      directories,
      arguments,
      invocation_directory,
      environment~,
      platform~,
    )
    let script_interpreter = evaluated_shell_setting(
      compilation, global, "script-interpreter",
    ).unwrap_or(
      @environment.ShellConfiguration::new("sh", ["-eu"]) catch {
        error => raise Environment(error)
      },
    )
    let setting_tempdir = evaluated_string_setting(
      compilation, global, "tempdir",
    )
    let temporary = @environment.resolve_temporary_directory(
      cwd,
      cli_tempdir=arguments.value("tempdir"),
      setting_tempdir~,
    ) catch {
      error => raise Environment(error)
    }
    let configuration = @planner.ScriptConfiguration::new(
      script_interpreter,
      temporary.directory().unwrap_or(cwd),
      platform,
    )
    runtimes[path] = @planner.ProjectModuleRuntime::new(
      global,
      evaluation_context,
      shell,
      cwd,
      environment,
      configuration,
      dotenv=dotenv_by_module[path],
    )
  }
  runtimes
}
