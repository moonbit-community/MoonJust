///|
fn[T : @host.HostFs] locate_interactive_justfile(
  host : T,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @workdir.WorkingDirectoryModel raise ApplicationError {
  if arguments.flag("global-justfile") {
    return global_input_directories(context).1
  }
  let working_directory = working_directory_argument(
    arguments,
    context.cwd().flavor(),
  )
  match input_selection(arguments, context.cwd().flavor()) {
    Stdin =>
      raise Query("interactive commands cannot use a justfile from stdin")
    File(path) => {
      let directories = @workdir.WorkingDirectoryModel::from_justfile(
        context.cwd(),
        path,
        working_directory~,
      ) catch {
        error => raise WorkingDirectory(error)
      }
      let justfile = directories.justfile().unwrap()
      let exists = @host.HostFs::file_exists(host, justfile) catch {
        error => raise Host(error)
      }
      if !exists {
        raise Query("justfile `" + justfile.as_string() + "` does not exist")
      }
      directories
    }
    Search => {
      let options = @loader.SearchOptions::new(
        filename=arguments.value("justfile-name").unwrap_or("justfile"),
        ceiling=ceiling_argument(arguments, context.cwd()),
      )
      let path = @loader.discover(host, context.cwd(), options~) catch {
        error => raise Load(error)
      }
      @workdir.WorkingDirectoryModel::from_justfile(context.cwd(), path) catch {
        error => raise WorkingDirectory(error)
      }
    }
  }
}

///|
fn interactive_failure(
  kind : String,
  command : String,
  termination : @host.ProcessTermination,
) -> ApplicationError {
  InteractiveProcess(kind~, command~, termination~)
}

///|
fn interactive_host_detail(error : @host.HostError) -> String {
  match error {
    InvalidInput(detail) if detail.contains("Permission denied") =>
      "Permission denied (os error 13)"
    InvalidInput(detail) if detail.contains("No such file or directory") =>
      "No such file or directory (os error 2)"
    InvalidInput(detail) => detail
    CapabilityDenied(capability) => "capability denied: \{Repr(capability)}"
    CapabilityUnavailable(capability) =>
      "capability unavailable: \{Repr(capability)}"
    NotFound(path) => "not found: " + path.as_string()
    AlreadyExists(path) => "already exists: " + path.as_string()
    PermissionDenied(_, detail~) =>
      if detail.contains("Permission denied") ||
        detail.contains("permission denied") {
        "Permission denied (os error 13)"
      } else {
        detail
      }
    UnexpectedProcess(_) | ProcessMismatch(_) => "unexpected process invocation"
    RandomExhausted(_) => "host randomness unavailable"
  }
}

///|
fn interactive_invocation_failure(
  kind : String,
  command : String,
  error : @host.HostError,
) -> ApplicationError {
  InteractiveInvocation(kind~, command~, detail=interactive_host_detail(error))
}

///|
/// Open the selected justfile without parsing it first. This is intentionally
/// usable as a recovery path for malformed source files.
pub async fn[F : @host.HostFs, E : @host.HostEnv, P : @host.HostAsyncProcess] execute_edit_command_async(
  filesystem : F,
  effects : E,
  process : P,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  if arguments.command() != EditCommand {
    raise UnsupportedCommand("editor execution for non-edit command")
  }
  if !arguments.positional().is_empty() {
    raise Query("`--edit` does not accept recipe arguments")
  }
  let directories = locate_interactive_justfile(filesystem, arguments, context)
  let visual = @host.HostEnv::env_get(effects, "VISUAL") catch {
    error => raise Host(error)
  }
  let editor = match visual {
    Some(value) => value
    None => {
      let configured = @host.HostEnv::env_get(effects, "EDITOR") catch {
        error => raise Host(error)
      }
      match configured {
        Some(value) => value
        None => "vim"
      }
    }
  }
  let justfile = directories.justfile().unwrap()
  let editor_path = @path.PathValue::new(
    editor,
    directories.project_directory().flavor(),
  ) catch {
    error => raise Path(error)
  }
  if editor_path.flavor() == Windows && editor_path.file_name() is None {
    raise InteractiveInvocation(
      kind="editor",
      command=editor,
      detail="program path has no file name",
    )
  }
  let spec = @host.CommandSpec::new(editor, [justfile.as_string()]) catch {
    error => raise Host(error)
  }
  spec.set_cwd(directories.project_directory())
  spec.set_inherit_stdin(true)
  spec.set_stdout(Inherit)
  spec.set_stderr(Inherit)
  let result = @host.HostAsyncProcess::run_process_async(process, spec) catch {
    error => raise interactive_invocation_failure("editor", editor, error)
  }
  match result.termination() {
    Exited(0) => @cli.ApplicationResponse::success()
    termination => raise interactive_failure("editor", editor, termination)
  }
}

///|
fn has_required_parameters(recipe : @syntax.Recipe) -> Bool {
  for parameter in recipe.parameters() {
    if parameter.default_value() is None &&
      (!parameter.variadic() || parameter.variadic_minimum() > 0) {
      return true
    }
  }
  false
}

///|
fn chooser_candidates(
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
) -> Array[String] raise ApplicationError {
  let requested_groups = arguments.values("group")
  for group in requested_groups {
    let mut exists = false
    for path in project.module_paths() {
      let compilation = project.module_compilation(path).unwrap()
      for name in compilation.recipe_names() {
        match compilation.recipe_attributes(name) {
          Some(attributes) if attributes.groups().contains(group) =>
            exists = true
          _ => ()
        }
      }
    }
    if !exists {
      raise Query("justfile does not contain group `" + group + "`")
    }
  }
  let candidates : Array[String] = []
  for path in project.module_paths() {
    let mut visible = true
    let mut current = Some(path)
    while current is Some(module_path) {
      if project
        .module_declaration_attributes(module_path)
        .any(fn(attribute) { attribute.name() == "private" }) {
        visible = false
        break
      }
      current = module_path.parent()
    }
    if !visible {
      continue
    }
    let compilation = project.module_compilation(path).unwrap()
    for name in compilation.recipe_names() {
      guard compilation.recipe(name) is Some(recipe) else { continue }
      guard compilation.recipe_attributes(name) is Some(attributes) else {
        continue
      }
      if name.has_prefix("_") ||
        attributes.private() ||
        has_required_parameters(recipe) ||
        project.recipe_disabled(path, name) {
        continue
      }
      if !requested_groups.is_empty() &&
        !requested_groups.any(fn(group) { attributes.groups().contains(group) }) {
        continue
      }
      candidates.push(
        if path.is_root() {
          name
        } else {
          path.as_string() + "::" + name
        },
      )
    }
  }
  candidates.sort_by(lexical_compare)
  candidates
}

///|
fn split_chooser_line(line : String) -> Array[String] {
  let values : Array[String] = []
  let mut builder = StringBuilder()
  let mut has_characters = false
  for character in line {
    if character == ' ' || character == '\t' || character == '\r' {
      if has_characters {
        values.push(builder.to_string())
        builder = StringBuilder()
        has_characters = false
      }
    } else {
      builder.write_char(character)
      has_characters = true
    }
  }
  if has_characters {
    values.push(builder.to_string())
  }
  values
}

///|
fn decode_chooser_selections(
  bytes : BytesView,
) -> Array[Array[String]] raise ApplicationError {
  let text = @utf8.decode(bytes) catch {
    _ => raise Query("chooser output is not valid UTF-8")
  }
  let selections : Array[Array[String]] = []
  for line in text.split("\n") {
    let arguments = split_chooser_line(line.to_owned())
    if !arguments.is_empty() {
      selections.push(arguments)
    }
  }
  selections
}

///|
/// Run the configured chooser and return one independent recipe invocation per
/// selected output line. Exit status 130 is the chooser cancellation contract.
#warnings("-unused_trait_bound")
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
  P : @host.HostAsyncProcess,
] execute_choose_command_async(
  filesystem : F,
  effects : H,
  process : P,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> Array[Array[String]] raise ApplicationError {
  if arguments.command() != ChooseCommand {
    raise UnsupportedCommand("chooser execution for non-choose command")
  }
  let loading_environment = @host.HostEnv::env_entries(effects) catch {
    error => raise Host(error)
  }
  let (graph, directories) = load_graph_input_with_directories_async(
    filesystem,
    arguments,
    context,
    environment=loading_environment,
  )
  let platform = @host.HostPlatform::platform_info(effects) catch {
    error => raise Host(error)
  }
  let project = compile_loaded_graph(
    graph,
    allow_unstable=arguments.flag("unstable"),
    platform=semantic_target_platform(platform),
  )
  let compilation = project.root()
  let overrides = variable_overrides(compilation, arguments)
  let cwd = directories.project_directory()
  let evaluation_context = @evaluator.EvaluationContext::new(
    cwd~,
    color_mode=arguments.value("color").unwrap_or("auto"),
  )
  let global = @evaluator.evaluate_compilation_with_async_effects(
    process,
    effects,
    compilation,
    evaluation_context,
    @evaluator.EffectShell::new("sh", ["-cu"]),
    overrides~,
  ) catch {
    error => raise Evaluation(error)
  }
  let candidates = chooser_candidates(project, arguments)
  if candidates.is_empty() {
    raise Query("justfile contains no choosable recipes")
  }
  let shell = selected_shell(compilation, global, arguments, cwd.flavor())
  let justfile = directories
    .justfile()
    .map(fn(path) { path.as_string() })
    .unwrap_or("-")
  let default_chooser = "fzf --multi --preview 'just --unstable --color always --justfile \"" +
    justfile +
    "\" --show {}'"
  let chooser = match arguments.value("chooser") {
    Some(value) => value
    None => {
      let configured = @host.HostEnv::env_get(effects, "JUST_CHOOSER") catch {
        error => raise Host(error)
      }
      match configured {
        Some(value) => value
        None => default_chooser
      }
    }
  }
  let shell_arguments = shell.arguments().to_owned()
  shell_arguments.push(chooser)
  let spec = @host.CommandSpec::new(shell.program(), shell_arguments) catch {
    error => raise Host(error)
  }
  spec.set_cwd(cwd)
  spec.set_stdin(@utf8.encode(candidates.join("\n") + "\n"))
  spec.set_stdout(Capture)
  spec.set_stderr(Inherit)
  let result = @host.HostAsyncProcess::run_process_async(process, spec) catch {
    error =>
      raise interactive_invocation_failure(
        "chooser",
        shell.program() + " " + shell_arguments.join(" "),
        error,
      )
  }
  match result.termination() {
    Exited(0) => decode_chooser_selections(result.stdout())
    Exited(130) => []
    termination => raise interactive_failure("chooser", chooser, termination)
  }
}
