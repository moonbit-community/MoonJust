///|
fn evaluated_shell_setting(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  name : String,
) -> @environment.ShellConfiguration? raise ApplicationError {
  match compilation.settings().get(name) {
    Some(Text(program)) => {
      let arguments = if name == "shell" { ["-cu"] } else { [] }
      Some(
        @environment.ShellConfiguration::new(program, arguments) catch {
          error => raise Environment(error)
        },
      )
    }
    Some(Expression(expression)) => {
      let value = @evaluator.evaluate_with_context(
        expression,
        @evaluator.EvaluationContext::new(lists=true),
        environment=global,
      ) catch {
        error => raise Evaluation(error)
      }
      let parts = value.elements()
      guard parts.get(0) is Some(program) else {
        raise Semantic(
          EmptySetting(
            name~,
            span=compilation.settings().span(name).unwrap_or(expression.span()),
          ),
        )
      }
      Some(
        @environment.ShellConfiguration::new(program, parts[1:].to_owned()) catch {
          error => raise Environment(error)
        },
      )
    }
    _ => None
  }
}

///|
fn evaluated_string_setting(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  name : String,
) -> String? raise ApplicationError {
  match compilation.settings().get(name) {
    Some(Text(value)) => Some(value)
    Some(Expression(expression)) => {
      let value = @evaluator.evaluate_with_context(
        expression,
        @evaluator.EvaluationContext::new(
          lists=compilation.settings().bool("lists"),
        ),
        environment=global,
      ) catch {
        error => raise Evaluation(error)
      }
      match value {
        String(value) => Some(value)
        value =>
          raise Semantic(
            ListsFeature(
              message=value.kind() +
                " value " +
                value.display() +
                " assigned to `" +
                name +
                "` setting",
              span=compilation
                .settings()
                .span(name)
                .unwrap_or(expression.span()),
            ),
          )
      }
    }
    _ => None
  }
}

///|
fn evaluated_const_string_setting(
  compilation : @semantic.Compilation,
  parent : @evaluator.Environment,
  overrides : ArrayView[(String, String)],
  name : String,
) -> String? raise ApplicationError {
  match compilation.settings().get(name) {
    Some(Text(value)) => Some(value)
    Some(Expression(expression)) => {
      let environment = @evaluator.LazyEnvironment::new(
        compilation,
        environment=@evaluator.Environment::child(parent),
      )
      environment.apply_overrides(overrides) catch {
        error => raise Evaluation(error)
      }
      let value = environment.evaluate_expression(expression) catch {
        error => raise Evaluation(error)
      }
      match value {
        String(value) => Some(value)
        value =>
          raise Semantic(
            ListsFeature(
              message=value.kind() +
                " value " +
                value.display() +
                " assigned to `" +
                name +
                "` setting",
              span=compilation
                .settings()
                .span(name)
                .unwrap_or(expression.span()),
            ),
          )
      }
    }
    _ => None
  }
}

///|
fn evaluated_const_shell_setting(
  compilation : @semantic.Compilation,
  parent : @evaluator.Environment,
  overrides : ArrayView[(String, String)],
  name : String,
) -> @environment.ShellConfiguration? raise ApplicationError {
  match compilation.settings().get(name) {
    Some(Text(program)) => {
      let arguments = if name == "shell" { ["-cu"] } else { [] }
      Some(
        @environment.ShellConfiguration::new(program, arguments) catch {
          error => raise Environment(error)
        },
      )
    }
    Some(Expression(expression)) => {
      let environment = @evaluator.LazyEnvironment::new(
        compilation,
        environment=@evaluator.Environment::child(parent),
      )
      environment.apply_overrides(overrides) catch {
        error => raise Evaluation(error)
      }
      let value = environment.evaluate_expression(expression) catch {
        error => raise Evaluation(error)
      }
      let parts = value.elements()
      guard parts.get(0) is Some(program) else {
        raise Semantic(
          EmptySetting(
            name~,
            span=compilation.settings().span(name).unwrap_or(expression.span()),
          ),
        )
      }
      Some(
        @environment.ShellConfiguration::new(program, parts[1:].to_owned()) catch {
          error => raise Environment(error)
        },
      )
    }
    _ => None
  }
}

///|
fn validate_no_recipe_variable_cycles(
  project : @semantic.ProjectCompilation,
) -> Unit raise ApplicationError {
  let compilation = project.root()
  guard compilation.recipe_names().is_empty() else { return }
  let environment = @evaluator.LazyEnvironment::new(compilation)
  for name in compilation.variable_names() {
    try ignore(environment.resolve(name)) catch {
      VariableCycle(..) as error => raise Evaluation(error)
      _ => ()
    } noraise {
      _ => ()
    }
  }
}

///|
fn validate_project_const_settings(
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
  flavor : @path.PathFlavor,
) -> Unit raise ApplicationError {
  fn const_setting_error(
    expression : @syntax.Expression,
    error : @evaluator.EvaluationError,
  ) -> ApplicationError {
    match error {
      EffectRequired(_) =>
        match expression {
          Variable(name~, span~) => Semantic(NonConstVariable(name~, span~))
          Backtick(literal) =>
            Semantic(ConstContext(kind="backticks", span=literal.span()))
          Call(name~, span~, ..) => {
            let name_span = @source.Span::new(
              span.source_id(),
              span.start_byte(),
              span.start_byte() + name.length(),
            ) catch {
              _ => span
            }
            Semantic(ConstContext(kind="functions", span=name_span))
          }
          _ => Evaluation(error)
        }
      _ => Evaluation(error)
    }
  }
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    let seed = @evaluator.Environment::new()
    @evaluator.install_constants(seed, flavor)
    let environment = @evaluator.LazyEnvironment::new(
      compilation,
      environment=seed,
    )
    let overrides = project_variable_overrides(project, path, arguments)
    environment.apply_overrides(overrides) catch {
      error => raise Evaluation(error)
    }
    for name in compilation.settings().names() {
      match compilation.settings().get(name) {
        Some(Expression(expression)) => {
          let value = environment.evaluate_expression(expression) catch {
            error => raise const_setting_error(expression, error)
          }
          if ["shell", "script-interpreter", "windows-shell"].contains(name) &&
            value.elements().is_empty() {
            raise Semantic(
              EmptySetting(
                name~,
                span=compilation
                  .settings()
                  .span(name)
                  .unwrap_or(expression.span()),
              ),
            )
          }
        }
        _ => ()
      }
    }
  }
}

///|
fn selected_shell_before_globals(
  compilation : @semantic.Compilation,
  parent : @evaluator.Environment,
  overrides : ArrayView[(String, String)],
  arguments : @cli.CliArguments,
  flavor : @path.PathFlavor,
) -> @environment.ShellConfiguration raise ApplicationError {
  let info = if flavor == Windows {
    @host.PlatformInfo::new(Windows, "unknown", Windows)
  } else {
    @host.PlatformInfo::new(Other("unix"), "unknown", Unix)
  }
  let platform = @environment.PlatformConfiguration::new(info)
  let setting_shell = evaluated_const_shell_setting(
    compilation, parent, overrides, "shell",
  )
  let windows_shell = evaluated_const_shell_setting(
    compilation, parent, overrides, "windows-shell",
  )
  @environment.resolve_shell(
    platform,
    cli_shell=arguments.value("shell"),
    cli_arguments=arguments.shell_arguments(),
    setting_shell~,
    windows_shell~,
    windows_powershell=compilation.settings().bool("windows-powershell"),
  ) catch {
    error => raise Environment(error)
  }
}

///|
fn selected_shell(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  arguments : @cli.CliArguments,
  flavor : @path.PathFlavor,
) -> @environment.ShellConfiguration raise ApplicationError {
  let info = if flavor == Windows {
    @host.PlatformInfo::new(Windows, "unknown", Windows)
  } else {
    @host.PlatformInfo::new(Other("unix"), "unknown", Unix)
  }
  let platform = @environment.PlatformConfiguration::new(info)
  let setting_shell = evaluated_shell_setting(compilation, global, "shell")
  let windows_shell = evaluated_shell_setting(
    compilation, global, "windows-shell",
  )
  @environment.resolve_shell(
    platform,
    cli_shell=arguments.value("shell"),
    cli_arguments=arguments.shell_arguments(),
    setting_shell~,
    windows_shell~,
    windows_powershell=compilation.settings().bool("windows-powershell"),
  ) catch {
    error => raise Environment(error)
  }
}

///|
fn[T : @host.HostTerminal] selected_color_active(
  effects : T,
  arguments : @cli.CliArguments,
) -> Bool raise ApplicationError {
  let mode = arguments.value("color").unwrap_or("auto")
  match mode {
    "always" => true
    "never" => false
    "auto" => {
      let terminal = @host.HostTerminal::terminal_info(effects) catch {
        error => raise Host(error)
      }
      terminal.color_supported() && terminal.stderr_is_terminal()
    }
    _ => raise Query("invalid --color value")
  }
}

///|
fn selected_command_color(
  arguments : @cli.CliArguments,
  color_active : Bool,
) -> @planner.CommandColor? raise ApplicationError {
  if !color_active || arguments.flag("no-highlight") {
    return None
  }
  guard arguments.value("command-color") is Some(value) else {
    return Some(Bold)
  }
  match value {
    "black" => Some(Black)
    "red" => Some(Red)
    "green" => Some(Green)
    "yellow" => Some(Yellow)
    "blue" => Some(Blue)
    "purple" => Some(Magenta)
    "cyan" => Some(Cyan)
    _ => raise Query("invalid --command-color value")
  }
}

///|
fn selected_jobs(arguments : @cli.CliArguments) -> Int raise ApplicationError {
  guard arguments.value("jobs") is Some(value) else { return 1 }
  let jobs = @string.parse_int(value[:]) catch {
    _ =>
      raise Query(
        "invalid --jobs value `\{value}`; expected a positive integer",
      )
  }
  if jobs <= 0 {
    raise Query("invalid --jobs value `\{value}`; expected a positive integer")
  }
  jobs
}

///|
fn execution_options(
  arguments : @cli.CliArguments,
  timestamp : String?,
  command_color : @planner.CommandColor?,
  color_enabled : Bool,
) -> @planner.ExecutionOptions raise ApplicationError {
  @planner.ExecutionOptions::from_values(
    arguments.flag("dry-run"),
    arguments.flag("quiet"),
    arguments.flag("verbose"),
    arguments.flag("time"),
    timestamp,
    command_color,
  )
  .with_jobs(selected_jobs(arguments))
  .with_cache(!arguments.flag("no-cache"))
  .with_unstable(arguments.flag("unstable"))
  .with_no_dependencies(arguments.flag("no-deps"))
  .with_explain(arguments.flag("explain"))
  .with_color_enabled(color_enabled)
  .with_verbosity(arguments.count("verbose"))
}

///|
