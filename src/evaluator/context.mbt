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
  utc_offset_seconds : Int?
} derive(Eq, Debug)

///|
pub fn EvaluationContext::new(
  cwd? : @path.PathValue,
  recipe? : String,
  module_name? : String,
  source? : @source.SourceId,
  justfile? : @path.PathValue,
  source_file? : @path.PathValue,
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
  utc_offset_seconds? : Int,
) -> EvaluationContext {
  {
    cwd,
    recipe,
    module_name,
    source,
    justfile,
    source_file,
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
    utc_offset_seconds,
  }
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
fn context_builtin(
  requested : String,
  arguments : Array[@value.Value],
  context : EvaluationContext,
  span : @source.Span,
) -> @value.Value? raise EvaluationError {
  let name = @builtin.canonical_name(requested)
  let value : @value.Value = match name {
    "absolute_path" => {
      let raw = expect_string(name, arguments, 0, span)
      String(resolve_context_path(context, raw, span).as_string())
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
        require_context_path(name, context.runtime_directory, span).as_string(),
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
        require_context_path(name, context.executable_directory, span).as_string(),
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
      match context.num_jobs {
        Some(value) => String(value.to_string())
        None => String("")
      }
    "is_dependency" => Bool(context.is_dependency)
    "recipe_name" => String(require_context_string(name, context.recipe, span))
    "just_version" => String("1.57.0")
    _ => return None
  }
  Some(value)
}
