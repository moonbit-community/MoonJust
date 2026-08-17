///|
/// Explicit invocation facts used by context and effect builtins. Optional
/// facts never fall back to fabricated values: requesting a missing fact
/// produces `EvaluationError::MissingContext`.
pub(all) struct EvaluationContext {
  cwd : @path.PathValue?
  recipe : String?
  module_name : String?
  source : @source.SourceId?
  justfile : @path.PathValue?
  source_file : @path.PathValue?
  source_files : Array[(@source.SourceId, @path.PathValue)]
  module_file : @path.PathValue?
  module_path : String?
  executable : @path.PathValue?
  executable_directory : @path.PathValue?
  invocation_directory : @path.PathValue?
  invocation_directory_native : @path.PathValue?
  home_directory : @path.PathValue?
  config_directory : @path.PathValue?
  config_local_directory : @path.PathValue?
  data_directory : @path.PathValue?
  data_local_directory : @path.PathValue?
  cache_directory : @path.PathValue?
  runtime_directory : @path.PathValue?
  pid : Int?
  num_cpus : Int?
  num_jobs : Int?
  is_dependency : Bool
  lists : Bool
  utc_offset_seconds : Int?
  color_mode : String?
  command_color : String?
  environment : Array[(String, String)]?
  process_environment : Array[(String, String)]?
} derive(Eq, Debug)

///|
pub fn EvaluationContext::new(
  cwd? : @path.PathValue,
  recipe? : String,
  module_name? : String,
  source? : @source.SourceId,
  justfile? : @path.PathValue,
  source_file? : @path.PathValue,
  source_files? : ArrayView[(@source.SourceId, @path.PathValue)] = [],
  module_file? : @path.PathValue,
  module_path? : String,
  executable? : @path.PathValue,
  executable_directory? : @path.PathValue,
  invocation_directory? : @path.PathValue,
  invocation_directory_native? : @path.PathValue,
  home_directory? : @path.PathValue,
  config_directory? : @path.PathValue,
  config_local_directory? : @path.PathValue,
  data_directory? : @path.PathValue,
  data_local_directory? : @path.PathValue,
  cache_directory? : @path.PathValue,
  runtime_directory? : @path.PathValue,
  pid? : Int,
  num_cpus? : Int,
  num_jobs? : Int,
  is_dependency? : Bool = false,
  lists? : Bool = false,
  utc_offset_seconds? : Int,
  color_mode? : String,
  command_color? : String,
  environment? : Array[(String, String)],
  process_environment? : Array[(String, String)],
) -> EvaluationContext {
  {
    cwd,
    recipe,
    module_name,
    source,
    justfile,
    source_file,
    source_files: source_files.to_owned(),
    module_file,
    module_path,
    executable,
    executable_directory,
    invocation_directory,
    invocation_directory_native,
    home_directory,
    config_directory,
    config_local_directory,
    data_directory,
    data_local_directory,
    cache_directory,
    runtime_directory,
    pid,
    num_cpus,
    num_jobs,
    is_dependency,
    lists,
    utc_offset_seconds,
    color_mode,
    command_color,
    environment,
    process_environment,
  }
}

///|
/// Derive a recipe context without discarding project- and module-level facts.
pub fn EvaluationContext::for_recipe(
  self : EvaluationContext,
  cwd : @path.PathValue,
  recipe : String,
  is_dependency : Bool,
) -> EvaluationContext {
  { ..self, cwd: Some(cwd), recipe: Some(recipe), is_dependency }
}

///|
/// Derive a context whose effectful expression evaluation inherits the given
/// process environment.
pub fn EvaluationContext::with_process_environment(
  self : EvaluationContext,
  environment : ArrayView[(String, String)],
) -> EvaluationContext {
  { ..self, process_environment: Some(environment.to_owned()) }
}

///|
pub fn EvaluationContext::color_mode(self : EvaluationContext) -> String? {
  self.color_mode
}

///|
pub fn EvaluationContext::command_color(self : EvaluationContext) -> String? {
  self.command_color
}

///|
pub fn EvaluationContext::cwd(self : EvaluationContext) -> @path.PathValue? {
  self.cwd
}

///|
pub fn EvaluationContext::recipe(self : EvaluationContext) -> String? {
  self.recipe
}

///|
pub fn EvaluationContext::module_name(self : EvaluationContext) -> String? {
  self.module_name
}

///|
pub fn EvaluationContext::source(self : EvaluationContext) -> @source.SourceId? {
  self.source
}

///|
pub fn EvaluationContext::justfile(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.justfile
}

///|
pub fn EvaluationContext::source_file(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.source_file
}

///|
pub fn EvaluationContext::for_source(
  self : EvaluationContext,
  source : @source.SourceId,
) -> EvaluationContext {
  let mut source_file = self.source_file
  for entry in self.source_files {
    if entry.0 == source {
      source_file = Some(entry.1)
      break
    }
  }
  { ..self, source: Some(source), source_file }
}

///|
pub fn EvaluationContext::module_file(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.module_file
}

///|
pub fn EvaluationContext::module_path(self : EvaluationContext) -> String? {
  self.module_path
}

///|
pub fn EvaluationContext::executable(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.executable
}

///|
pub fn EvaluationContext::executable_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.executable_directory
}

///|
pub fn EvaluationContext::invocation_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.invocation_directory
}

///|
pub fn EvaluationContext::invocation_directory_native(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.invocation_directory_native
}

///|
pub fn EvaluationContext::home_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.home_directory
}

///|
pub fn EvaluationContext::config_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.config_directory
}

///|
pub fn EvaluationContext::config_local_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.config_local_directory
}

///|
pub fn EvaluationContext::data_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.data_directory
}

///|
pub fn EvaluationContext::data_local_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.data_local_directory
}

///|
pub fn EvaluationContext::cache_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.cache_directory
}

///|
pub fn EvaluationContext::runtime_directory(
  self : EvaluationContext,
) -> @path.PathValue? {
  self.runtime_directory
}

///|
pub fn EvaluationContext::pid(self : EvaluationContext) -> Int? {
  self.pid
}

///|
pub fn EvaluationContext::num_cpus(self : EvaluationContext) -> Int? {
  self.num_cpus
}

///|
pub fn EvaluationContext::num_jobs(self : EvaluationContext) -> Int? {
  self.num_jobs
}

///|
pub fn EvaluationContext::is_dependency(self : EvaluationContext) -> Bool {
  self.is_dependency
}

///|
pub fn EvaluationContext::lists(self : EvaluationContext) -> Bool {
  self.lists
}

///|
pub fn EvaluationContext::utc_offset_seconds(self : EvaluationContext) -> Int? {
  self.utc_offset_seconds
}

///|
fn require_context_path(
  fact : String,
  value : @path.PathValue?,
  span : @source.Span,
) -> @path.PathValue raise EvaluationError {
  match value {
    Some(path) => path
    None => raise MissingContext(fact~, span~)
  }
}

///|
fn require_function_path(
  name : String,
  value : @path.PathValue?,
  missing : String,
  span : @source.Span,
) -> @path.PathValue raise EvaluationError {
  match value {
    Some(path) => path
    None =>
      raise Builtin(
        Failure(message="call to function `" + name + "` failed: " + missing),
        span~,
      )
  }
}

///|
fn require_context_string(
  fact : String,
  value : String?,
  span : @source.Span,
) -> String raise EvaluationError {
  match value {
    Some(text) => text
    None => raise MissingContext(fact~, span~)
  }
}

///|
fn require_context_int(
  fact : String,
  value : Int?,
  span : @source.Span,
) -> Int raise EvaluationError {
  match value {
    Some(number) => number
    None => raise MissingContext(fact~, span~)
  }
}

///|
fn resolve_context_path(
  context : EvaluationContext,
  raw : String,
  span : @source.Span,
) -> @path.PathValue raise EvaluationError {
  let cwd = require_context_path("cwd", context.cwd, span)
  let path = @path.PathValue::new(raw, cwd.flavor()) catch {
    _ => raise TypeMismatch(expected="path", actual=raw, span~)
  }
  if path.is_absolute() {
    path.clean()
  } else {
    let resolved = cwd.join(path) catch {
      _ => raise TypeMismatch(expected="path", actual=raw, span~)
    }
    resolved.clean()
  }
}

///|
fn context_parent(
  fact : String,
  value : @path.PathValue?,
  span : @source.Span,
) -> @path.PathValue raise EvaluationError {
  let path = require_context_path(fact, value, span)
  match path.parent() {
    Some(parent) => parent
    None => raise MissingContext(fact=fact + " parent", span~)
  }
}

///|
fn split_ascii_whitespace(value : String) -> Array[String] {
  let words : Array[String] = []
  let mut current = StringBuilder()
  for character in value {
    if character.is_ascii_whitespace() {
      if !current.is_empty() {
        words.push(current.to_string())
        current = StringBuilder()
      }
    } else {
      current.write_char(character)
    }
  }
  if !current.is_empty() {
    words.push(current.to_string())
  }
  words
}

///|
fn context_boolean(
  context : EvaluationContext,
  condition : Bool,
) -> @value.Value {
  if context.lists {
    if condition {
      String("true")
    } else {
      List([])
    }
  } else {
    String(condition.to_string())
  }
}

///|
fn map_context_paths(
  value : @value.Value,
  context : EvaluationContext,
  span : @source.Span,
) -> @value.Value raise EvaluationError {
  let result : Array[@value.Value] = []
  for raw in value.elements() {
    result.push(String(resolve_context_path(context, raw, span).as_string()))
  }
  match result {
    [single] => single
    values => List(values)
  }
}

///|
fn context_builtin(
  requested : String,
  arguments : Array[@value.Value],
  context : EvaluationContext,
  span : @source.Span,
) -> @value.Value? raise EvaluationError {
  let name = @builtin.canonical_name(requested)
  let value : @value.Value = match name {
    "bool" => {
      if !context.lists {
        raise Builtin(
          Failure(message="the `bool()` function requires `set lists`"),
          span~,
        )
      }
      let elements = arguments[0].elements()
      let condition = match elements {
        [] => false
        [""] | ["0"] | ["false"] => false
        ["1"] | ["true"] => true
        [value] =>
          raise Builtin(
            Failure(
              message="call to function `bool` failed: `\{value}` is not a valid boolean string",
            ),
            span~,
          )
        _ =>
          raise Builtin(
            Failure(
              message="call to function `bool` failed: multi-element lists cannot be converted into booleans",
            ),
            span~,
          )
      }
      if condition {
        String("true")
      } else {
        List([])
      }
    }
    "append" | "prepend" => {
      if arguments.length() != 2 {
        return None
      }
      let affix = expect_string(name, arguments, 0, span)
      let elements = if context.lists {
        arguments[1].elements()
      } else {
        split_ascii_whitespace(arguments[1].to_string())
      }
      let mapped : Array[@value.Value] = []
      for element in elements {
        mapped.push(
          String(
            if name == "append" {
              element + affix
            } else {
              affix + element
            },
          ),
        )
      }
      if context.lists {
        List(mapped)
      } else {
        String(mapped.map(fn(value) { value.to_string() }).join(" "))
      }
    }
    "show" => {
      if !context.lists {
        raise Builtin(
          Failure(message="the `show()` function requires `set lists`"),
          span~,
        )
      }
      String(arguments[0].display())
    }
    "join_list" | "split" => {
      if !context.lists {
        raise Builtin(
          Failure(message="the `\{name}()` function requires `set lists`"),
          span~,
        )
      }
      return None
    }
    "quote" => {
      if !context.lists {
        let value = @builtin.call("quote", [String(arguments[0].to_string())]) catch {
          error => raise Builtin(error, span~)
        }
        return Some(value)
      }
      let quoted : Array[@value.Value] = []
      for element in arguments[0].elements() {
        let value = @builtin.call("quote", [String(element)]) catch {
          error => raise Builtin(error, span~)
        }
        quoted.push(value)
      }
      match quoted {
        [single] => single
        values => List(values)
      }
    }
    "semver_matches" => {
      let result = @builtin.call(name, arguments) catch {
        error => raise Builtin(error, span~)
      }
      context_boolean(context, result.truthy())
    }
    "env" | "env_var" | "env_var_or_default" => {
      guard context.environment is Some(entries) else { return None }
      let keys = arguments[0].elements()
      for key in keys {
        for entry in entries {
          if entry.0 == key {
            return Some(String(entry.1))
          }
        }
      }
      if (name == "env" || name == "env_var_or_default") &&
        arguments.length() > 1 {
        return Some(arguments[1])
      }
      let description = if keys.is_empty() {
        "empty environment variable list with no default"
      } else if keys.length() == 1 {
        "environment variable `" + keys[0] + "` not present"
      } else {
        "environment variables " +
        keys.map(fn(key) { "`" + key + "`" }).join(" and ") +
        " not present"
      }
      raise Builtin(
        Failure(
          message="call to function `" + requested + "` failed: " + description,
        ),
        span~,
      )
    }
    "absolute_path" =>
      if context.lists {
        map_context_paths(arguments[0], context, span)
      } else {
        String(
          resolve_context_path(context, arguments[0].to_string(), span).as_string(),
        )
      }
    "cache_directory" =>
      String(
        require_context_path(name, context.cache_directory, span).as_string(),
      )
    "config_directory" =>
      String(
        require_context_path(name, context.config_directory, span).as_string(),
      )
    "config_local_directory" =>
      String(
        require_context_path(name, context.config_local_directory, span).as_string(),
      )
    "data_directory" =>
      String(
        require_context_path(name, context.data_directory, span).as_string(),
      )
    "data_local_directory" =>
      String(
        require_context_path(name, context.data_local_directory, span).as_string(),
      )
    "home_directory" =>
      String(
        require_context_path(name, context.home_directory, span).as_string(),
      )
    "runtime_directory" =>
      String(
        require_function_path(
          name,
          context.runtime_directory,
          "runtime directory not found",
          span,
        ).as_string(),
      )
    "invocation_directory" =>
      String(
        require_context_path(name, context.invocation_directory, span).as_string(),
      )
    "invocation_directory_native" =>
      String(
        require_context_path(name, context.invocation_directory_native, span).as_string(),
      )
    "executable_directory" =>
      String(
        require_function_path(
          name,
          context.executable_directory,
          "executable directory not found",
          span,
        ).as_string(),
      )
    "justfile_directory" =>
      String(context_parent("justfile", context.justfile, span).as_string())
    "source_directory" =>
      String(
        context_parent("source_file", context.source_file, span).as_string(),
      )
    "module_directory" =>
      String(
        context_parent("module_file", context.module_file, span).as_string(),
      )
    "just_executable" =>
      String(require_context_path(name, context.executable, span).as_string())
    "justfile" =>
      String(require_context_path(name, context.justfile, span).as_string())
    "source_file" =>
      String(require_context_path(name, context.source_file, span).as_string())
    "module_file" =>
      String(require_context_path(name, context.module_file, span).as_string())
    "module_path" =>
      String(require_context_string(name, context.module_path, span))
    "just_pid" =>
      String(require_context_int(name, context.pid, span).to_string())
    "num_cpus" =>
      String(require_context_int(name, context.num_cpus, span).to_string())
    "num_jobs" =>
      if !context.lists {
        raise Builtin(
          Failure(message="the `num_jobs()` function requires `set lists`"),
          span~,
        )
      } else {
        match context.num_jobs {
          Some(value) => String(value.to_string())
          None => List([])
        }
      }
    "is_dependency" => context_boolean(context, context.is_dependency)
    "recipe_name" =>
      String(
        match context.recipe {
          Some(recipe) => recipe
          None =>
            raise Builtin(
              Failure(
                message="call to function `recipe_name` failed: `recipe_name()` can only be used within a recipe",
              ),
              span~,
            )
        },
      )
    "just_version" => String("1.57.0")
    _ => return None
  }
  Some(value)
}
