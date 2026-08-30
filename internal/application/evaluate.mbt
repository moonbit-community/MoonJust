///|
fn shell_escape(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character == '!' ||
      character == '"' ||
      character == '$' ||
      character == '\\' ||
      character == '`' {
      builder.write_char('\\')
    }
    builder.write_char(character)
  }
  builder.to_string()
}

///|
fn joined_value(value : @value.Value) -> String {
  value.to_string()
}

///|
fn just_value(value : @value.Value) -> String {
  value.display()
}

///|
fn colored_just_value(value : @value.Value) -> String {
  let text = value.display()
  let characters = text.to_array()
  let builder = StringBuilder()
  builder.write_string("\u{001b}[32m")
  let mut index = 0
  while index < characters.length() {
    if characters[index] == '\\' && index + 1 < characters.length() {
      builder.write_string("\u{001b}[36m")
      builder.write_char(characters[index])
      builder.write_char(characters[index + 1])
      builder.write_string("\u{001b}[32m")
      index += 2
    } else {
      builder.write_char(characters[index])
      index += 1
    }
  }
  builder.write_string("\u{001b}[0m")
  builder.to_string()
}

///|
fn evaluate_text(
  compilation : @semantic.Compilation,
  ast : @syntax.Ast,
  arguments : @cli.CliArguments,
) -> String raise ApplicationError {
  let environment = @evaluator.LazyEnvironment::new(compilation)
  let overrides = variable_overrides(compilation, arguments)
  environment.apply_overrides(overrides) catch {
    error => raise Evaluation(error)
  }
  match arguments.positional().get(0) {
    Some(name) =>
      joined_value(
        environment.resolve(name) catch {
          error => raise Evaluation(error)
        },
      )
    None => {
      let private = private_assignments(ast)
      let names = compilation.variable_names().to_owned()
      names.sort_by(lexical_compare)
      let mut maximum = 0
      for name in names {
        if !private.contains(name) {
          maximum = Int::max(maximum, name.length())
        }
      }
      let builder = StringBuilder()
      let shell = arguments.value("evaluate-format") == Some("shell")
      for name in names {
        if private.contains(name) {
          continue
        }
        let value = environment.resolve(name) catch {
          error => raise Evaluation(error)
        }
        if shell {
          guard compilation.variable(name) is Some(assignment) else { continue }
          if assignment.exported() || compilation.settings().bool("export") {
            builder.write_string("export ")
          }
          builder.write_string(name.replace(old="-", new="_"))
          builder.write_string("=\"")
          builder.write_string(shell_escape(joined_value(value)))
          builder.write_string("\"\n")
        } else {
          builder.write_string(name)
          for _ in name.length()..<maximum {
            builder.write_char(' ')
          }
          builder.write_string(" := ")
          builder.write_string(
            if arguments.value("color") == Some("always") {
              colored_just_value(value)
            } else {
              just_value(value)
            },
          )
          builder.write_char('\n')
        }
      }
      builder.to_string()
    }
  }
}

///|
fn evaluated_environment_text(
  compilation : @semantic.Compilation,
  ast : @syntax.Ast,
  arguments : @cli.CliArguments,
  environment : @evaluator.Environment,
  selected? : String,
) -> String raise ApplicationError {
  match selected {
    Some(name) =>
      match environment.get(name) {
        Some(value) => joined_value(value)
        None => raise Query("variable `" + name + "` is not defined")
      }
    None => {
      let private = private_assignments(ast)
      let names = compilation.variable_names().to_owned()
      names.sort_by(lexical_compare)
      let mut maximum = 0
      for name in names {
        if !private.contains(name) {
          maximum = Int::max(maximum, name.length())
        }
      }
      let builder = StringBuilder()
      let shell = arguments.value("evaluate-format") == Some("shell")
      for name in names {
        if private.contains(name) {
          continue
        }
        guard environment.get(name) is Some(value) else { continue }
        if shell {
          guard compilation.variable(name) is Some(assignment) else { continue }
          if assignment.exported() || compilation.settings().bool("export") {
            builder.write_string("export ")
          }
          builder.write_string(name.replace(old="-", new="_"))
          builder.write_string("=\"")
          builder.write_string(shell_escape(joined_value(value)))
          builder.write_string("\"\n")
        } else {
          builder.write_string(name)
          for _ in name.length()..<maximum {
            builder.write_char(' ')
          }
          builder.write_string(" := ")
          builder.write_string(
            if arguments.value("color") == Some("always") {
              colored_just_value(value)
            } else {
              just_value(value)
            },
          )
          builder.write_char('\n')
        }
      }
      builder.to_string()
    }
  }
}

///|
fn evaluation_path(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
) -> (@modulepath.ModulePath, String?) raise ApplicationError {
  if arguments.is_empty() {
    return (@modulepath.ModulePath::root(), None)
  }
  if arguments.length() != 1 {
    raise Query(
      "`--evaluate` used with unexpected argument: `" + arguments[1] + "`",
    )
  }
  let requested = arguments[0]
  let root = @modulepath.ModulePath::root()
  if project.root().variable(requested) is Some(_) {
    return (root, Some(requested))
  }
  match project.resolve_module(root, requested) {
    Some(path) => return (path, None)
    None => ()
  }
  let full = @modulepath.ModulePath::parse(requested) catch {
    _ => raise Query("invalid evaluation path `" + arguments[0] + "`")
  }
  let components = full.components().to_owned()
  guard components.pop() is Some(name) else {
    return (@modulepath.ModulePath::root(), None)
  }
  if components.is_empty() {
    let names = project.root().variable_names().to_owned()
    names.append(direct_submodule_names(project, root))
    let base = "justfile does not contain variable or submodule `" + name + "`"
    raise Query(
      match closest_name(name, names) {
        Some(suggestion) => base + "\nDid you mean `" + suggestion + "`?"
        None => base
      },
    )
  }
  let parent = components.join("::")
  if project.absent_module_for_reference(root, parent) is Some(absent) {
    raise Query("optional module `" + absent.as_string() + "` is absent")
  }
  let path = match project.resolve_module(root, parent) {
    Some(path) => path
    None =>
      raise Query(
        unknown_submodule_message(project, root, components[0], display=parent),
      )
  }
  (path, Some(name))
}

///|
pub async fn[
  F : @host.HostFs + @host.HostSourceReader,
  P : @host.HostAsyncProcess,
  H : @host.HostFs + @host.HostEnv + @host.HostClock + @host.HostRandom + @host.HostPlatform + @host.HostTerminal,
] execute_evaluate_command_async(
  filesystem : F,
  effects : H,
  process : P,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @cli.ApplicationResponse raise ApplicationError {
  if arguments.command() != EvaluateCommand {
    raise UnsupportedCommand("async evaluation for non-evaluate command")
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
  let (path, selected) = evaluation_path(project, arguments.positional())
  let invocation_directory = shell_invocation_directory(
    process, directories, arguments, platform,
  )
  let (globals, _) = evaluate_project_globals_async(
    filesystem,
    process,
    effects,
    project,
    directories,
    arguments,
    platform,
    loading_environment,
    invocation_directory,
    evaluation_target=(path, selected),
  )
  guard project.module_compilation(path) is Some(compilation) else {
    raise Query("unknown module `" + path.as_string() + "`")
  }
  guard loaded_for_module(graph, path) is Some(loaded) else {
    raise Query("source for module `" + path.as_string() + "` is unavailable")
  }
  let output = evaluated_environment_text(
    compilation,
    loaded.ast(),
    arguments,
    globals[path],
    selected?,
  )
  @cli.ApplicationResponse::success(stdout=@utf8.encode(output))
}

///|
