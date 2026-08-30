///|
async fn[
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] invocation_values_async(
  process : P,
  host : H,
  compilation : @semantic.Compilation,
  invocation : @invocation.Invocation,
  global : @evaluator.Environment,
  context : @evaluator.EvaluationContext,
  shell : @environment.ShellConfiguration,
) -> Array[@value.Value] raise ApplicationError {
  guard compilation.recipe(invocation.recipe()) is Some(recipe) else {
    raise Query("recipe `\{invocation.recipe()}` does not exist")
  }
  let scope = @evaluator.Environment::child(global)
  let result : Array[@value.Value] = []
  let effect_shell = @evaluator.EffectShell::new(
    shell.program(),
    shell.arguments().to_owned(),
  )
  for index, parameter in recipe.parameters() {
    let raw_elements = invocation.arguments()[index].elements()
    let elements : Array[String] = []
    let value_expression = @invocation.recipe_argument_value_expression(
      compilation,
      invocation.recipe(),
      parameter.name(),
    ) catch {
      error => raise Invocation(error)
    }
    match value_expression {
      Some(expression) if !raw_elements.is_empty() =>
        for _ in raw_elements {
          let value = @evaluator.evaluate_with_async_effects(
            process,
            host,
            expression,
            context,
            effect_shell,
            environment=scope,
          ) catch {
            error => raise Evaluation(error)
          }
          elements.append(value.elements())
        }
      _ => elements.append(raw_elements)
    }
    if parameter.variadic() {
      let elements = if elements.is_empty() {
        match parameter.default_value() {
          Some(expression) =>
            (@evaluator.evaluate_with_async_effects(
              process,
              host,
              expression,
              context,
              effect_shell,
              environment=scope,
            ) catch {
              error => raise Evaluation(error)
            }).elements()
          None => elements.map(fn(element) { element })
        }
      } else {
        elements.map(fn(element) { element })
      }
      for element in elements {
        result.push(String(element))
      }
      scope.set(
        parameter.name(),
        List(elements.map(fn(element) { String(element) })),
      )
    } else if invocation.arguments()[index].list() {
      let value : @value.Value = List(
        elements.map(fn(element) { String(element) }),
      )
      result.push(value)
      scope.set(parameter.name(), value)
    } else {
      let value : @value.Value = match elements.length() {
        // Preserve an empty argument as a default-value sentinel. The
        // planner evaluates the default after recipe `[env]` attributes have
        // been applied to the effect process context.
        0 => List([])
        1 => String(elements[0])
        _ => List(elements.map(fn(element) { String(element) }))
      }
      result.push(value)
      scope.set(parameter.name(), value)
    }
  }
  result
}

///|
async fn[
  F : @host.HostFs + @host.HostSourceReader,
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] evaluate_project_globals_async(
  filesystem : F,
  process : P,
  effects : H,
  project : @semantic.ProjectCompilation,
  directories : @workdir.WorkingDirectoryModel,
  arguments : @cli.CliArguments,
  platform : @host.PlatformInfo,
  loading_environment : ArrayView[(String, String)],
  invocation_directory : @path.PathValue,
  targets? : ArrayView[(@modulepath.ModulePath, String)],
  evaluation_target? : (@modulepath.ModulePath, String?),
) -> (
  Map[@modulepath.ModulePath, @evaluator.Environment],
  Map[@modulepath.ModulePath, Array[(String, String)]],
) raise ApplicationError {
  validate_project_variable_overrides(project, arguments)
  let globals : Map[@modulepath.ModulePath, @evaluator.Environment] = Map([])
  let dotenv_by_module : Map[@modulepath.ModulePath, Array[(String, String)]] = Map([],
  )
  for path in project.module_paths() {
    let seed = match path.parent() {
      Some(parent) =>
        match globals.get(parent) {
          Some(environment) => @evaluator.Environment::module_scope(environment)
          None => @evaluator.Environment::new()
        }
      None => @evaluator.Environment::new()
    }
    let compilation = project.module_compilation(path).unwrap()
    @evaluator.install_constants(seed, platform.path_flavor())
    for name in compilation.unexports() {
      seed.remove(name)
    }
    let base = project_module_base(project, directories, path)
    let overrides = project_variable_overrides(project, path, arguments)
    let working_directory = evaluated_const_string_setting(
      compilation, seed, overrides, "working-directory",
    )
    let evaluation_cwd = project_module_cwd(
      project, directories, path, working_directory, false,
    )
    let inherited_dotenv = match path.parent() {
      Some(parent) => dotenv_by_module.get(parent).unwrap_or([])
      None => []
    }
    let ambient = process_environment(
      loading_environment,
      seed,
      base.flavor(),
      unexports=compilation.unexports(),
    )
    let dotenv_shell = selected_shell_before_globals(
      compilation,
      seed,
      overrides,
      arguments,
      base.flavor(),
    )
    let (_, dotenv) = compose_dotenv_environment_async(
      filesystem,
      process,
      platform.portable_runtime(),
      compilation,
      arguments,
      seed,
      base,
      ambient,
      dotenv_shell,
      path.is_root(),
    )
    perf_detail_mark("run.global.dotenv")
    let evaluation_environment = merge_dotenv_entries(
      merge_dotenv_entries(ambient, inherited_dotenv, true),
      dotenv,
      true,
    )
    dotenv_by_module[path] = merge_dotenv_entries(
      inherited_dotenv.copy(),
      dotenv,
      true,
    )
    let evaluation_context = project_evaluation_context(
      project,
      path,
      evaluation_cwd,
      directories,
      arguments,
      invocation_directory,
      environment=evaluation_environment,
      platform~,
    )
    let mut lazy_enabled = compilation.settings().bool("lazy")
    let mut parent = path.parent()
    while parent is Some(parent_path) {
      let parent_compilation = project.module_compilation(parent_path).unwrap()
      if parent_compilation.settings().bool("lazy") {
        lazy_enabled = true
      }
      parent = parent_path.parent()
    }
    let selected_recipes : Array[String] = []
    match targets {
      Some(targets) =>
        for target in targets {
          if target.0 == path {
            selected_recipes.push(target.1)
          }
        }
      None => ()
    }
    let selected = match evaluation_target {
      Some((target_path, target_name)) => {
        let names : Array[String] = if path == target_path {
          match target_name {
            Some(name) => [name]
            None => compilation.variable_names().to_owned()
          }
        } else {
          []
        }
        if target_path.starts_with(path) && path != target_path {
          for name in compilation.variable_names() {
            guard compilation.variable(name) is Some(assignment) else {
              continue
            }
            if assignment.eager() ||
              assignment.exported() ||
              compilation.settings().bool("export") {
              names.push(name)
            }
          }
        }
        names
      }
      None =>
        if lazy_enabled && targets is Some(_) {
          let names = @evaluator.recipe_variable_references(
            compilation, selected_recipes,
          )
          for name in compilation.variable_names() {
            guard compilation.variable(name) is Some(assignment) else {
              continue
            }
            if assignment.eager() ||
              assignment.exported() ||
              compilation.settings().bool("export") {
              if !names.contains(name) {
                names.push(name)
              }
            }
          }
          names
        } else {
          compilation.variable_names().to_owned()
        }
    }
    let global = @evaluator.evaluate_compilation_with_async_effects_selected(
      process,
      effects,
      compilation,
      evaluation_context,
      @evaluator.EffectShell::new(
        dotenv_shell.program(),
        dotenv_shell.arguments().to_owned(),
      ),
      selected,
      environment=seed,
      overrides~,
      quiet=arguments.flag("quiet"),
      dry_run=arguments.flag("dry-run"),
    ) catch {
      error => raise Evaluation(error)
    }
    perf_detail_mark("run.global.evaluate")
    globals[path] = global
  }
  (globals, dotenv_by_module)
}

///|
/// Async application boundary. All parsing, semantic work, invocation
/// validation, and effectful interpolation are complete before runtime steps
/// are handed to the process adapter.
async fn[
  F : @host.HostFs + @host.HostSourceReader,
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] plan_run_command_async(
  filesystem : F,
  effects : H,
  process : P,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @planner.ExecutionPlan raise ApplicationError {
  if arguments.command() != RunCommand {
    raise UnsupportedCommand("execution planning for non-run command")
  }
  let (arguments, context) = search_prefixed_invocation(arguments, context)
  let platform = @host.HostPlatform::platform_info(effects) catch {
    error => raise Host(error)
  }
  perf_detail_mark("run.platform")
  let loading_environment = @host.HostEnv::env_entries(effects) catch {
    error => raise Host(error)
  }
  perf_detail_mark("run.environment")
  let mut current_context = context
  let mut fallback_depth = 0
  let fallback_stderr = StringBuilder()
  while true {
    let prepared = if fallback_depth == 0 {
      take_prepared_run_project(
        arguments, current_context, platform, loading_environment,
      )
    } else {
      None
    }
    let (directories, project) = match prepared {
      Some(snapshot) => {
        perf_detail_mark("run.preloaded")
        (snapshot.directories(), snapshot.compilation())
      }
      None => {
        let (graph, directories) = load_graph_input_with_directories_async(
          filesystem,
          arguments,
          current_context,
          platform=semantic_target_platform(platform),
          environment=loading_environment,
        )
        perf_detail_mark("run.load")
        let project = compile_loaded_graph(
          graph,
          allow_unstable=arguments.flag("unstable"),
          platform=semantic_target_platform(platform),
        ) catch {
          Semantic(error) if fallback_depth > 0 => {
            for file in graph.files() {
              if file.source().id() == error.span().source_id() {
                raise ContextualSemantic(
                  error~,
                  source=file.source(),
                  cwd=current_context.cwd(),
                )
              }
            }
            raise Semantic(error)
          }
          error => raise error
        }
        perf_detail_mark("run.compile")
        (directories, project)
      }
    }
    validate_project_const_settings(project, arguments, platform.path_flavor())
    validate_no_recipe_variable_cycles(project)
    validate_project_variable_overrides(project, arguments)
    let targets = try
      @invocation.parse_project_invocation_targets(
        project,
        arguments.positional(),
        allow_missing=arguments.flag("allow-missing"),
      )
    catch {
      UnknownRecipe(_)
      | UnknownRecipeSuggested(_)
      | UnknownSubmodule(_) as missing if project
        .root()
        .settings()
        .bool("fallback") &&
        arguments.value("justfile") is None &&
        arguments.value("working-directory") is None &&
        !arguments.flag("global-justfile") => {
        guard directories.justfile() is Some(justfile) else {
          raise Invocation(missing)
        }
        guard justfile.parent() is Some(directory) else {
          raise Invocation(missing)
        }
        guard directory.parent() is Some(parent) else {
          raise Invocation(missing)
        }
        let options = @loader.SearchOptions::new(
          filename=arguments.value("justfile-name").unwrap_or("justfile"),
          ceiling=ceiling_argument(arguments, current_context.cwd()),
        )
        try @loader.discover(filesystem, parent, options~) catch {
          NoJustfileFound(_) => raise Invocation(missing)
          error => raise Load(error)
        } noraise {
          _ => ()
        }
        current_context = current_context.with_cwd(parent)
        fallback_depth += 1
        if arguments.flag("verbose") {
          fallback_stderr.write_string("Trying ")
          for _ in 0..<fallback_depth {
            fallback_stderr.write_string(
              ".." + platform.path_flavor().separator().to_string(),
            )
          }
          fallback_stderr.write_string("justfile\n")
        }
        continue
      }
      error => raise Invocation(error)
    } noraise {
      value => value
    }
    perf_detail_mark("run.invocations")
    let sync_dry_run = arguments.flag("dry-run") &&
      !arguments.flag("explain") &&
      @planner.supports_sync_dry_run(project)
    let pure_sync_globals = sync_dry_run &&
      project_supports_pure_sync_globals(project, arguments)
    let invocation_directory = shell_invocation_directory(
      process, directories, arguments, platform,
    )
    let (globals, dotenv_by_module) = if pure_sync_globals {
      let globals = evaluate_project_globals(
        project,
        arguments,
        flavor=platform.path_flavor(),
      )
      let dotenv_by_module : Map[
        @modulepath.ModulePath,
        Array[(String, String)],
      ] = Map([])
      for path in project.module_paths() {
        dotenv_by_module[path] = []
      }
      (globals, dotenv_by_module)
    } else {
      evaluate_project_globals_async(
        filesystem,
        process,
        effects,
        project,
        directories,
        arguments,
        platform,
        loading_environment,
        invocation_directory,
        targets~,
      )
    }
    perf_detail_mark("run.globals")
    let invocations = @invocation.parse_project_invocations_in_environments(
      project,
      arguments.positional(),
      globals,
      allow_missing=arguments.flag("allow-missing"),
      resolve_expressions=false,
    ) catch {
      error => raise Invocation(error)
    }
    if arguments.flag("one") && invocations.length() != 1 {
      raise Query(
        "expected 1 command-line recipe invocation but found " +
        invocations.length().to_string(),
      )
    }
    perf_detail_mark("run.runtime_setup")
    let timestamp = selected_timestamp(effects, arguments)
    let color_enabled = selected_color_active(effects, arguments)
    let command_color = selected_command_color(arguments, color_enabled)
    let options = execution_options(
      arguments, timestamp, command_color, color_enabled,
    )
    let cache_directory = cache_directory(directories.module_directory())
    let runtimes : Array[@planner.ProjectModuleRuntime] = []
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
      let environment = process_environment(
        loading_environment,
        global,
        evaluation_cwd.flavor(),
        unexports=compilation.unexports(),
      )
      let environment = merge_dotenv_entries(
        environment,
        dotenv_by_module[path],
        compilation.settings().bool("dotenv-override"),
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
        InvalidOverridePath(path~) =>
          raise Environment(InvalidOverridePath(path~))
        EmptyShell => raise Environment(EmptyShell)
        Path(error) => raise Environment(Path(error))
      }
      let configuration = @planner.ScriptConfiguration::new(
        script_interpreter,
        temporary.directory().unwrap_or(cwd),
        platform,
      )
      runtimes.push(
        @planner.ProjectModuleRuntime::new(
          path, global, evaluation_context, shell, cwd, environment, configuration,
        ),
      )
    }
    let requests : Array[@planner.ProjectRecipeRequest] = []
    if sync_dry_run {
      let plans : Array[@planner.ExecutionPlan] = []
      for project_invocation in invocations {
        let path = project_invocation.module_path()
        let invocation = project_invocation.invocation()
        let compilation = project.module_compilation(path).unwrap()
        let global = globals[path]
        let mut selected_runtime : @planner.ProjectModuleRuntime? = None
        for runtime in runtimes {
          if runtime.module_path() == path {
            selected_runtime = Some(runtime)
            break
          }
        }
        let runtime = selected_runtime.unwrap()
        let values = invocation_values(compilation, invocation, global)
        let plan = @planner.plan_recipe_graph(
          compilation,
          [@planner.RecipeRequest::new(invocation.recipe(), arguments=values)],
          global,
          runtime.shell(),
          runtime.cwd(),
          process_environment=runtime.process_environment(),
          options=options.with_echo_quiet(
            options.echo_quiet() || compilation.settings().bool("quiet"),
          ),
        ) catch {
          error => raise Planner(error)
        }
        plans.push(plan)
      }
      let combined = @planner.combine_execution_plans(plans)
      perf_detail_mark("run.sync_plan")
      ignore(perf_detail_emit() catch { _ => () })
      let prefix = fallback_stderr.to_string()
      if prefix == "" {
        return combined
      }
      return combined.with_stderr_prefix(@utf8.encode(prefix))
    }
    for project_invocation in invocations {
      let path = project_invocation.module_path()
      let invocation = project_invocation.invocation()
      let compilation = project.module_compilation(path).unwrap()
      let global = globals[path]
      let mut selected_runtime : @planner.ProjectModuleRuntime? = None
      for runtime in runtimes {
        if runtime.module_path() == path {
          selected_runtime = Some(runtime)
          break
        }
      }
      let runtime = selected_runtime.unwrap()
      let values = invocation_values_async(
        process,
        effects,
        compilation,
        invocation,
        global,
        runtime.context().for_recipe(runtime.cwd(), invocation.recipe(), false),
        runtime.shell(),
      )
      requests.push(
        @planner.ProjectRecipeRequest::new(
          path,
          invocation.recipe(),
          arguments=values,
        ),
      )
    }
    let combined = @planner.plan_project_recipe_graph_async(
      process,
      effects,
      project,
      requests,
      runtimes,
      options~,
      cache_directory~,
    ) catch {
      error => raise Planner(error)
    }
    perf_detail_mark("run.async_plan")
    ignore(perf_detail_emit() catch { _ => () })
    let prefix = fallback_stderr.to_string()
    if prefix == "" {
      return combined
    }
    return combined.with_stderr_prefix(@utf8.encode(prefix))
  }
  raise Query("fallback planning did not terminate")
}
