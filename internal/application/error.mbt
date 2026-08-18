///|
/// Failures raised while composing pure packages with explicit host input.
pub(all) suberror ApplicationError {
  Cli(@cli.CliParseError)
  Load(@loader.LoaderError)
  Format(@formatter.FormatterError)
  Evaluation(@evaluator.EvaluationError)
  Environment(@environment.EnvironmentConfigError)
  Dotenv(@environment.DotenvError)
  Executor(@executor.ExecutionError)
  Host(@host.HostError)
  Invocation(@invocation.InvocationError)
  Path(@path.PathError)
  Project(@semantic.ProjectCompilationError)
  Semantic(@semantic.SemanticError)
  ContextualSemantic(
    error~ : @semantic.SemanticError,
    source~ : @source.Source,
    cwd~ : @path.PathValue
  )
  WorkingDirectory(@workdir.WorkingDirectoryError)
  InteractiveInvocation(kind~ : String, command~ : String, detail~ : String)
  InteractiveProcess(
    kind~ : String,
    command~ : String,
    termination~ : @host.ProcessTermination
  )
  DotenvCommand(command~ : String, exit_code~ : Int)
  WriteJustfile(path~ : @path.PathValue, detail~ : String)
  AlreadyExists(@path.PathValue)
  Query(String)
  UnsupportedCommand(String)
} derive(Debug)

///|
pub fn ApplicationError::exit_code(self : ApplicationError) -> Int {
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
    Executor(error) => error.exit_code()
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
    | ContextualSemantic(_)
    | WorkingDirectory(_)
    | InteractiveInvocation(_)
    | WriteJustfile(_)
    | AlreadyExists(_)
    | Query(_) => 1
  }
}

///|
pub fn ApplicationError::message(self : ApplicationError) -> String {
  match self {
    Cli(Invalid(message)) | Cli(Config(message)) => message
    Cli(Unsupported(name)) => "error: option '\{name}' is not supported yet"
    Load(error) => "error: \{error.message()}"
    Format(error) => "error: \{error.message()}"
    Evaluation(error) => "error: evaluation failed: \{Repr(error)}"
    Environment(error) => "error: " + error.message()
    Dotenv(error) => "error: " + error.message()
    Executor(error) => error.message()
    Host(error) => "error: host operation failed: \{Repr(error)}"
    Invocation(error) => "error: " + error.message()
    Path(error) => "error: invalid path: \{Repr(error)}"
    Project(error) => "error: invalid project compilation: \{Repr(error)}"
    Semantic(error) => "error: \{error.message()}"
    ContextualSemantic(error~, ..) => "error: \{error.message()}"
    WorkingDirectory(error) => "error: \{error.message()}"
    InteractiveInvocation(kind="command", command~, detail~) =>
      "error: failed to invoke \{command}: \{detail}"
    InteractiveInvocation(kind~, command~, detail~) =>
      "error: \{kind} `\{command}` invocation failed: \{detail}"
    InteractiveProcess(kind="command", command~, termination=Exited(code)) =>
      "error: command \{command} failed: exit status: \{code}"
    InteractiveProcess(kind~, command~, termination=Exited(code)) =>
      "error: \{kind} `\{command}` failed: exit status: \{code}"
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
      "error: failed to write justfile to `" + path.as_string() + "`: " + detail
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
    Executor(Evaluation(evaluation)) =>
      "error[" + evaluation.code() + "]: " + evaluation.message()
    _ => error.message()
  }
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
        display = path.as_string().view(start_offset=prefix.length()).to_owned()
      }
    }
    _ => ()
  }
  @source.Source::from_bytes(source.id(), display, source.bytes().to_owned()) catch {
    _ => source
  }
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
/// Render source-backed semantic and evaluation failures. Other application
/// errors retain their stable one-line diagnostics because they do not carry a
/// source span that can be validated against the loaded graph.
pub fn[T : @host.HostFs] render_application_error(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
  error : ApplicationError,
) -> String {
  match error {
    Evaluation(UnknownOverrides(..) as evaluation) =>
      return "error: " + evaluation.message()
    Evaluation(EmptyParameter(..) as evaluation) =>
      return "error: " + evaluation.message()
    Executor(Evaluation(EmptyParameter(..) as evaluation)) =>
      return "error: " + evaluation.message()
    Evaluation(FunctionRecursionLimit(..) as evaluation) =>
      return "error: " + evaluation.message()
    _ => ()
  }
  let diagnostic = match error {
    Load(error) =>
      match error.span() {
        Some(span) => Some(error.to_diagnostic(span)) catch { _ => None }
        None => None
      }
    Semantic(error) | ContextualSemantic(error~, ..) =>
      Some(error.to_diagnostic()) catch {
        _ => None
      }
    Evaluation(error) => Some(error.to_diagnostic()) catch { _ => None }
    Invocation(error) => error.to_diagnostic() catch { _ => None }
    Executor(error) => error.to_diagnostic() catch { _ => None }
    _ => None
  }
  guard diagnostic is Some(diagnostic) else {
    return stable_application_error_message(error)
  }
  let sources = @source.SourceMap::new()
  let render_cwd = match error {
    ContextualSemantic(cwd~, ..) => cwd
    Load(_) => diagnostic_load_cwd(arguments, context.cwd())
    _ => context.cwd()
  }
  let direct_source = match error {
    Load(error) => error.diagnostic_source()
    ContextualSemantic(source~, ..) => Some(source)
    _ => None
  }
  match direct_source {
    Some(source) =>
      try sources.add(diagnostic_source(source, render_cwd)) catch {
        _ => return stable_application_error_message(error)
      } noraise {
        _ => ()
      }
    None => {
      let graph = try
        load_graph_input_with_directories(host, arguments, context).0
      catch {
        _ => {
          let loaded = try
            load_input_with_directories(host, arguments, context).0
          catch {
            _ => return stable_application_error_message(error)
          } noraise {
            value => value
          }
          try
            sources.add(diagnostic_source(loaded.source(), render_cwd))
          catch {
            _ => return stable_application_error_message(error)
          } noraise {
            _ => ()
          }
          return @diagnostic.render_text(diagnostic, sources) catch {
            _ => stable_application_error_message(error)
          }
        }
      } noraise {
        value => value
      }
      for file in graph.files() {
        try sources.add(diagnostic_source(file.source(), render_cwd)) catch {
          _ => return stable_application_error_message(error)
        } noraise {
          _ => ()
        }
      }
    }
  }
  @diagnostic.render_text(diagnostic, sources) catch {
    _ => stable_application_error_message(error)
  }
}

///|
/// Async counterpart used by production command paths. Source recovery for a
/// diagnostic observes the same bounded-read contract as the initial load.
pub async fn[T : @host.HostFs + @host.HostSourceReader] render_application_error_async(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
  error : ApplicationError,
) -> String {
  match error {
    Evaluation(UnknownOverrides(..) as evaluation) =>
      return "error: " + evaluation.message()
    Evaluation(EmptyParameter(..) as evaluation) =>
      return "error: " + evaluation.message()
    Executor(Evaluation(EmptyParameter(..) as evaluation)) =>
      return "error: " + evaluation.message()
    Evaluation(FunctionRecursionLimit(..) as evaluation) =>
      return "error: " + evaluation.message()
    _ => ()
  }
  let diagnostic = match error {
    Load(error) =>
      match error.span() {
        Some(span) => Some(error.to_diagnostic(span)) catch { _ => None }
        None => None
      }
    Semantic(error) | ContextualSemantic(error~, ..) =>
      Some(error.to_diagnostic()) catch {
        _ => None
      }
    Evaluation(error) => Some(error.to_diagnostic()) catch { _ => None }
    Invocation(error) => error.to_diagnostic() catch { _ => None }
    Executor(error) => error.to_diagnostic() catch { _ => None }
    _ => None
  }
  guard diagnostic is Some(diagnostic) else {
    return stable_application_error_message(error)
  }
  let sources = @source.SourceMap::new()
  let render_cwd = match error {
    ContextualSemantic(cwd~, ..) => cwd
    Load(_) => diagnostic_load_cwd(arguments, context.cwd())
    _ => context.cwd()
  }
  let direct_source = match error {
    Load(error) => error.diagnostic_source()
    ContextualSemantic(source~, ..) => Some(source)
    _ => None
  }
  match direct_source {
    Some(source) =>
      try sources.add(diagnostic_source(source, render_cwd)) catch {
        _ => return stable_application_error_message(error)
      } noraise {
        _ => ()
      }
    None => {
      let graph = try
        load_graph_input_with_directories_async(host, arguments, context).0
      catch {
        _ => {
          let loaded = try
            load_input_with_directories_async(host, arguments, context).0
          catch {
            _ => return stable_application_error_message(error)
          } noraise {
            value => value
          }
          try
            sources.add(diagnostic_source(loaded.source(), render_cwd))
          catch {
            _ => return stable_application_error_message(error)
          } noraise {
            _ => ()
          }
          return @diagnostic.render_text(diagnostic, sources) catch {
            _ => stable_application_error_message(error)
          }
        }
      } noraise {
        value => value
      }
      for file in graph.files() {
        try sources.add(diagnostic_source(file.source(), render_cwd)) catch {
          _ => return stable_application_error_message(error)
        } noraise {
          _ => ()
        }
      }
    }
  }
  @diagnostic.render_text(diagnostic, sources) catch {
    _ => stable_application_error_message(error)
  }
}
