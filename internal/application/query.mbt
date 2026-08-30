///|
fn default_list_module_path(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
) -> @modulepath.ModulePath? {
  if arguments.is_empty() {
    return Some(@modulepath.ModulePath::root())
  }
  let requested = if arguments.length() == 1 {
    arguments[0]
  } else {
    arguments.join("::")
  }
  project.resolve_module(@modulepath.ModulePath::root(), requested)
}

///|
/// Return a list response when `--default-list` or the selected module's
/// `default-list` setting applies. Explicit recipe invocations return `None`.
pub fn[
  F : @host.HostFs,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_default_list_command(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse? raise ApplicationError {
  guard arguments.command() == RunCommand else { return None }
  let (arguments, context) = search_prefixed_invocation(arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  let (graph, _) = load_graph_input_with_directories(
    host,
    arguments,
    context,
    platform=semantic_platform,
    environment=loading_environment,
  )
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_platform,
  )
  guard default_list_module_path(project, arguments.positional()) is Some(path) else {
    return None
  }
  let compilation = project.module_compilation(path).unwrap()
  if !arguments.flag("default-list") &&
    !compilation.settings().bool("default-list") {
    return None
  }
  let color = match arguments.value("color").unwrap_or("auto") {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(terminal_host) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stdout_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  let builder = StringBuilder()
  builder.write_string(
    arguments.value("list-heading").unwrap_or("Available recipes:\n"),
  )
  let globals = evaluate_project_globals(project, arguments)
  append_project_list_module(
    builder, graph, project, path, arguments, color, 0, globals,
  )
  Some(
    @cli.ApplicationResponse::success(stdout=@utf8.encode(builder.to_string())),
  )
}

///|
/// Bounded-source variant used by the native and wasm CLI entry points.
#warnings("-unused_async-unused_trait_bound")
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_default_list_command_async(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse? raise ApplicationError {
  clear_prepared_run_project()
  guard arguments.command() == RunCommand else { return None }
  let (arguments, context) = search_prefixed_invocation(arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("run.preflight.platform")
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("run.preflight.environment")
  let snapshot = load_project_snapshot_async(
    host, arguments, context, semantic_platform, loading_environment,
  )
  let graph = snapshot.graph()
  perf_detail_mark("run.preflight.load")
  let project = snapshot.compilation()
  perf_detail_mark("run.preflight.compile")
  guard default_list_module_path(project, arguments.positional()) is Some(path) else {
    cache_prepared_run_project(
      arguments, context, platform, loading_environment, snapshot,
    )
    return None
  }
  let compilation = project.module_compilation(path).unwrap()
  if !arguments.flag("default-list") &&
    !compilation.settings().bool("default-list") {
    cache_prepared_run_project(
      arguments, context, platform, loading_environment, snapshot,
    )
    return None
  }
  let color = match arguments.value("color").unwrap_or("auto") {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(terminal_host) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stdout_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  let builder = StringBuilder()
  builder.write_string(
    arguments.value("list-heading").unwrap_or("Available recipes:\n"),
  )
  let globals = evaluate_project_globals(project, arguments)
  append_project_list_module(
    builder, graph, project, path, arguments, color, 0, globals,
  )
  Some(
    @cli.ApplicationResponse::success(stdout=@utf8.encode(builder.to_string())),
  )
}

///|
fn query_text(
  loaded : @loader.LoadedSource,
  compilation : @semantic.Compilation,
  arguments : @cli.CliArguments,
  color : Bool,
) -> String raise ApplicationError {
  match arguments.command() {
    ListCommand => list_text(loaded, compilation, arguments, color)
    ShowCommand => show_text(loaded, compilation, arguments)
    SummaryCommand =>
      @query.visible_recipe_names(compilation, @query.build_query(arguments)).join(
        " ",
      ) +
      "\n"
    UsageCommand => usage_text(compilation, arguments)
    VariablesCommand => {
      let private = private_assignments(loaded.ast())
      let values : Array[String] = []
      for name in compilation.variable_names() {
        if !private.contains(name) {
          values.push(name)
        }
      }
      if values.is_empty() {
        ""
      } else {
        values.sort_by(@query.lexical_compare)
        values.join(" ") + "\n"
      }
    }
    GroupsCommand => {
      if !arguments.positional().is_empty() {
        raise Query(
          "`--groups` used with unexpected argument: `" +
          arguments.positional()[0] +
          "`",
        )
      }
      let groups : Array[String] = []
      for
        name in @query.visible_recipe_names(
          compilation,
          @query.build_query(arguments),
        ) {
        match compilation.recipe_attributes(name) {
          Some(value) =>
            for group in value.groups() {
              if !groups.contains(group) {
                groups.push(group)
              }
            }
          None => ()
        }
      }
      let values = groups
      if !arguments.flag("unsorted") {
        values.sort_by(@query.lexical_compare)
      }
      if values.is_empty() {
        ""
      } else {
        "Recipe groups:\n" +
        values
        .map(fn(value) {
          arguments.value("list-prefix").unwrap_or("    ") + value
        })
        .join("\n") +
        "\n"
      }
    }
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
}

///|
fn[
  F : @host.HostFs,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_query_command_with_terminal(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  let (arguments, context) = query_search_prefix(host, arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  let (graph, _) = load_graph_input_with_directories(
    host,
    arguments,
    context,
    platform=semantic_platform,
    environment=loading_environment,
  )
  match @query.try_fast_summary(graph, @query.build_query(arguments)) {
    Some(result) =>
      return @cli.ApplicationResponse::success(
        stdout=result.stdout().to_owned(),
        stderr=result.stderr().to_owned(),
      )
    None => ()
  }
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_platform,
  )
  validate_project_variable_overrides(project, arguments)
  let color = match arguments.value("color").unwrap_or("auto") {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(terminal_host) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stdout_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  let output = query_project_text(graph, project, arguments, color)
  let stderr = if arguments.command() == SummaryCommand &&
    !arguments.flag("quiet") &&
    output == "\n" {
    b"justfile contains no recipes\n"
  } else {
    b""
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output), stderr~)
}

///|
pub fn[
  T : @host.HostFs + @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_query_command(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  execute_query_command_with_terminal(host, host, arguments, context)
}

///|
#warnings("-unused_async-unused_trait_bound")
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
  T : @host.HostEnv + @host.HostTerminal + @host.HostPlatform,
] execute_query_command_with_terminal_async(
  host : F,
  terminal_host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  let (arguments, context) = query_search_prefix(host, arguments, context)
  let platform = @host.HostPlatform::platform_info(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("query.platform")
  let semantic_platform = semantic_target_platform(platform)
  let loading_environment = @host.HostEnv::env_entries(terminal_host) catch {
    error => raise Host(error)
  }
  perf_detail_mark("query.environment")
  let (graph, _) = load_graph_input_with_directories_async(
    host,
    arguments,
    context,
    platform=semantic_platform,
    environment=loading_environment,
  )
  perf_detail_mark("query.load")
  match @query.try_fast_summary(graph, @query.build_query(arguments)) {
    Some(result) => {
      ignore(perf_detail_emit() catch { _ => () })
      return @cli.ApplicationResponse::success(
        stdout=result.stdout().to_owned(),
        stderr=result.stderr().to_owned(),
      )
    }
    None => ()
  }
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_platform,
  )
  perf_detail_mark("query.compile")
  validate_project_variable_overrides(project, arguments)
  let color = match arguments.value("color").unwrap_or("auto") {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(terminal_host) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stdout_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
  let output = query_project_text(graph, project, arguments, color)
  perf_detail_mark("query.render")
  ignore(perf_detail_emit() catch { _ => () })
  let stderr = if arguments.command() == SummaryCommand &&
    !arguments.flag("quiet") &&
    output == "\n" {
    b"justfile contains no recipes\n"
  } else {
    b""
  }
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output), stderr~)
}
