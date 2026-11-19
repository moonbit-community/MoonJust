///|
/// Failures raised while composing pure packages with explicit host input.
#derive(Debug)
pub(all) suberror ApplicationError {
  Cli(@cli.CliParseError)
  Load(@loader.LoaderError)
  Format(@formatter.FormatterError)
  Evaluation(@evaluator.EvaluationError)
  Environment(@environment.EnvironmentConfigError)
  Dotenv(@environment.DotenvError)
  Planner(@planner.ExecutionError)
  Host(@host.HostError)
  Invocation(@invocation.InvocationError)
  Path(@path.PathError)
  Project(@semantic.ProjectCompilationError)
  Semantic(@semantic.SemanticError)
  AtProject(ApplicationError, @loader.LoadedGraph?, @path.PathValue)
  WorkingDirectory(@workdir.WorkingDirectoryError)
  InteractiveInvocation(kind~ : String, command~ : String, detail~ : String)
  InteractiveProcess(
    kind~ : String,
    command~ : String,
    termination~ : @host.ProcessTermination,
  )
  DotenvCommand(command~ : String, exit_code~ : Int32)
  WriteJustfile(path~ : String, detail~ : String)
  AlreadyExists(@path.PathValue)
  Query(String)
  UnsupportedCommand(String)
}

///|
fn ApplicationError::with_project_sources(
  self : ApplicationError,
  graph : @loader.LoadedGraph,
  cwd : @path.PathValue,
) -> ApplicationError {
  match self {
    AtProject(_, _, _) => self
    _ => AtProject(self, Some(graph), cwd)
  }
}

///|
fn process_exit_label() -> String {
  if @async.platform is Windows {
    "exit code"
  } else {
    "exit status"
  }
}

///|
fn ApplicationError::exit_code(self : ApplicationError) -> Int32 {
  match self {
    Cli(_) | UnsupportedCommand(_) => 2
    InteractiveProcess(termination=Exited(code), ..) => code
    InteractiveProcess(termination=Signaled(signal), ..) => signal.exit_code()
    InteractiveProcess(termination=Interrupted(signal), ..) =>
      signal.exit_code()
    DotenvCommand(exit_code~, ..) => exit_code
    Evaluation(ProcessFailure(code~, ..)) => code
    Evaluation(BacktickFailure(code~, ..)) => code
    Evaluation(ProcessSignaled(signal~, ..)) => signal.exit_code()
    AtProject(error, _, _) => error.exit_code()
    Planner(error) => error.exit_code()
    Dotenv(error) => error.exit_code()
    Load(_)
    | Format(_)
    | Evaluation(_)
    | Environment(_)
    | Host(_)
    | Invocation(_)
    | Path(_)
    | Project(_)
    | Semantic(_)
    | WorkingDirectory(_)
    | InteractiveInvocation(_)
    | WriteJustfile(_)
    | AlreadyExists(_)
    | Query(_) => 1
  }
}

///|
fn ApplicationError::message(self : ApplicationError) -> String {
  match self {
    Cli(Invalid(message)) | Cli(Config(message)) => message
    Cli(Unsupported(name)) => "error: option '\{name}' is not supported yet"
    Load(error) => "error: \{error.message()}"
    Format(error) => "error: \{error.message()}"
    Evaluation(error) => "error: evaluation failed: \{Repr(error)}"
    Environment(error) => "error: " + error.message()
    Dotenv(error) => "error: " + error.message()
    Planner(error) => error.message()
    Host(error) => "error: host operation failed: \{Repr(error)}"
    Invocation(error) => "error: " + error.message()
    Path(error) => "error: invalid path: \{Repr(error)}"
    Project(error) => "error: invalid project compilation: \{Repr(error)}"
    Semantic(error) => "error: \{error.message()}"
    AtProject(error, _, _) => error.message()
    WorkingDirectory(error) => "error: \{error.message()}"
    InteractiveInvocation(kind="command", command~, detail~) =>
      "error: failed to invoke \{command}: \{detail}"
    InteractiveInvocation(kind~, command~, detail~) =>
      "error: \{kind} `\{command}` invocation failed: \{detail}"
    InteractiveProcess(kind="command", command~, termination=Exited(code)) =>
      "error: command \{command} failed: \{process_exit_label()}: \{code}"
    InteractiveProcess(kind~, command~, termination=Exited(code)) =>
      "error: \{kind} `\{command}` failed: \{process_exit_label()}: \{code}"
    InteractiveProcess(kind="command", command~, termination=Signaled(signal)) =>
      "error: command \{command} terminated by signal \{signal.number()}"
    InteractiveProcess(kind~, command~, termination=Signaled(signal)) => {
      let name = match signal {
        Hangup => "SIGHUP"
        Interrupt => "SIGINT"
        Terminate => "SIGTERM"
        OtherSignal(value) => "SIG" + value.to_string()
      }
      "error: \{kind} `\{command}` failed: signal: \{signal.number()} (\{name})"
    }
    InteractiveProcess(termination=Interrupted(signal), ..) =>
      "error: interrupted by " + signal.name()
    DotenvCommand(command~, exit_code~) =>
      "error: dotenv command `" +
      command +
      "` failed: process exited with status code " +
      exit_code.to_string()
    WriteJustfile(path~, detail~) =>
      "error: failed to write justfile to `" + path + "`: " + detail
    AlreadyExists(path) =>
      "error: justfile `\{path.as_string()}` already exists"
    Query(message) => "error: \{message}"
    UnsupportedCommand(name) => "error: command '\{name}' is not supported yet"
  }
}

///|
fn stable_application_error_message(error : ApplicationError) -> String {
  match error {
    Evaluation(evaluation) =>
      "error[" + evaluation.code() + "]: " + evaluation.message()
    Planner(Evaluation(evaluation)) =>
      "error[" + evaluation.code() + "]: " + evaluation.message()
    Planner(InvalidAttributeValue(message~, ..)) => "error: " + message
    _ => error.message()
  }
}

///|
fn color_error_message(
  arguments : @cli.CliArguments,
  message : String,
) -> String {
  guard arguments.value("color") == Some("always") &&
    !message.contains("\u{001b}[") &&
    message.strip_prefix("error: ") is Some(detail) else {
    return message
  }
  "\u{001b}[1;31merror\u{001b}[0m: \u{001b}[1m" +
  detail.trim_end().to_owned() +
  "\u{001b}[0m"
}

///|
fn diagnostic_source(
  source : @source.Source,
  cwd : @path.PathValue,
) -> @source.Source {
  let original = source.name()
  let mut display = if original == "<stdin>" { "justfile" } else { original }
  let path = try @path.PathValue::new(original, cwd.flavor()) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  match path {
    Some(path) if @loader.is_markdown_path(path) => display = "justfile"
    Some(path) if path.is_absolute() && cwd.is_absolute() => {
      let separator = cwd.flavor().separator().to_string()
      let prefix = if cwd.as_string().has_suffix(separator) {
        cwd.as_string()
      } else {
        cwd.as_string() + separator
      }
      if path.as_string().has_prefix(prefix) {
        display = path.as_string()[prefix.length():].to_owned()
      }
    }
    _ => ()
  }
  source.with_name(display)
}

///|
fn diagnostic_load_cwd(
  arguments : @cli.CliArguments,
  cwd : @path.PathValue,
) -> @path.PathValue {
  guard arguments.value("justfile") is Some(value) && value != "-" else {
    return cwd
  }
  let selected = try @path.PathValue::new(value, cwd.flavor()) catch {
    _ => return cwd
  } noraise {
    path => path
  }
  let absolute = if selected.is_absolute() {
    selected
  } else {
    try cwd.join(selected) catch {
      _ => return cwd
    } noraise {
      path => path
    }
  }
  absolute.parent().unwrap_or(cwd)
}

///|
fn render_application_error(
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
  error : ApplicationError,
) -> String {
  let (error, graph, cwd) = match error {
    AtProject(cause, graph, cwd) => (cause, graph, cwd)
    _ => (error, None, context.cwd())
  }
  match error {
    Load(ImportCycle(_))
    | Semantic(
      CachedRecipesUnstable(_)
      | UserFunctionsUnstable(_)
      | ListsUnstable(_),
    )
    | Planner(CachedRecipesUnstable) => return error.message()
    Evaluation(
      UnknownOverrides(..)
      | EmptyParameter(..)
      | FunctionRecursionLimit(..) as evaluation,
    )
    | Planner(Evaluation(EmptyParameter(..) as evaluation)) =>
      return "error: " + evaluation.message()
    _ => ()
  }
  let diagnostic = match error {
    Load(error) =>
      match error.span() {
        Some(span) => Some(error.to_diagnostic(span)) catch { _ => None }
        None => None
      }
    Semantic(error) => Some(error.to_diagnostic()) catch { _ => None }
    Evaluation(error) => Some(error.to_diagnostic()) catch { _ => None }
    Invocation(error) => error.to_diagnostic() catch { _ => None }
    Planner(error) => error.to_diagnostic() catch { _ => None }
    _ => None
  }
  guard diagnostic is Some(diagnostic) else {
    return stable_application_error_message(error)
  }
  let sources = @source.SourceMap::new()
  try {
    match error {
      Load(load) =>
        if load.diagnostic_source() is Some(source) {
          sources.add(
            diagnostic_source(source, diagnostic_load_cwd(arguments, cwd)),
          )
        }
      _ =>
        if graph is Some(graph) {
          for file in graph.files() {
            sources.add(diagnostic_source(file.source(), cwd))
          }
        }
    }
    if arguments.value("color") == Some("always") {
      @diagnostic.render_colored_text(diagnostic, sources)
    } else {
      @diagnostic.render_text(diagnostic, sources)
    }
  } catch {
    _ => stable_application_error_message(error)
  }
}
