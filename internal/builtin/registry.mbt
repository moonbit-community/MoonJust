///|
/// Names of pure builtins supported by the evaluator.
type Value = @value.Value

///|
pub(all) enum BuiltinPurity {
  Pure
  Effect
} derive(Eq, Debug)

///|
pub(all) enum BuiltinCapability {
  Context
  FsRead
  Environment
  Clock
  Random
  Process
  Platform
  Terminal
} derive(Eq, Debug)

///|
pub(all) enum BuiltinTarget {
  Native
  Wasm1
} derive(Eq, Debug)

///|
pub(all) struct BuiltinSpec {
  name : String
  purity : BuiltinPurity
  min_arguments : Int
  max_arguments : Int?
  aliases : Array[String]
  capabilities : Array[BuiltinCapability]
  targets : Array[BuiltinTarget]
  evidence : String
} derive(Eq, Debug)

///|
pub fn BuiltinSpec::name(self : BuiltinSpec) -> String {
  self.name
}

///|
pub fn BuiltinSpec::purity(self : BuiltinSpec) -> BuiltinPurity {
  self.purity
}

///|
pub fn BuiltinSpec::min_arguments(self : BuiltinSpec) -> Int {
  self.min_arguments
}

///|
pub fn BuiltinSpec::max_arguments(self : BuiltinSpec) -> Int? {
  self.max_arguments
}

///|
pub fn BuiltinSpec::aliases(self : BuiltinSpec) -> ArrayView[String] {
  self.aliases[:]
}

///|
pub fn BuiltinSpec::capabilities(
  self : BuiltinSpec,
) -> ArrayView[BuiltinCapability] {
  self.capabilities[:]
}

///|
pub fn BuiltinSpec::targets(self : BuiltinSpec) -> ArrayView[BuiltinTarget] {
  self.targets[:]
}

///|
pub fn BuiltinSpec::evidence(self : BuiltinSpec) -> String {
  self.evidence
}

///|
pub fn BuiltinSpec::accepts_arity(self : BuiltinSpec, actual : Int) -> Bool {
  actual >= self.min_arguments &&
  (match self.max_arguments {
    Some(maximum) => actual <= maximum
    None => true
  })
}

///|
pub fn BuiltinSpec::arity_description(self : BuiltinSpec) -> String {
  match self.max_arguments {
    Some(maximum) =>
      if maximum == self.min_arguments {
        maximum.to_string()
      } else {
        self.min_arguments.to_string() + " or " + maximum.to_string()
      }
    None => self.min_arguments.to_string() + " or more"
  }
}

///|
pub fn names() -> ArrayView[String] {
  [
    "absolute_path", "append", "arch", "blake3", "blake3_file", "bool", "cache_directory",
    "canonicalize", "capitalize", "choose", "clean", "config_directory", "config_local_directory",
    "data_directory", "data_local_directory", "datetime", "datetime_utc", "encode_uri_component",
    "env", "env_var", "env_var_or_default", "error", "executable_directory", "extension",
    "file_name", "file_stem", "home_directory", "invocation_directory", "invocation_directory_native",
    "is_dependency", "join", "join_list", "just_executable", "just_pid", "just_version",
    "justfile", "justfile_directory", "kebabcase", "len", "lowercamelcase", "lowercase",
    "module_directory", "module_file", "module_path", "num_cpus", "num_jobs", "os",
    "os_family", "parent_directory", "path_exists", "prepend", "quote", "read", "recipe_name",
    "replace", "replace_regex", "require", "runtime_directory", "semver_matches",
    "sha256", "sha256_file", "shell", "shoutykebabcase", "shoutysnakecase", "show",
    "snakecase", "source_directory", "source_file", "split", "style", "titlecase",
    "trim", "trim_end", "trim_end_match", "trim_end_matches", "trim_start", "trim_start_match",
    "trim_start_matches", "uppercamelcase", "uppercase", "uuid", "which", "without_extension",
  ][:]
}

///|
fn builtin_arity(name : String) -> (Int, Int?) {
  match name {
    "arch"
    | "cache_directory"
    | "config_directory"
    | "config_local_directory"
    | "data_directory"
    | "data_local_directory"
    | "executable_directory"
    | "home_directory"
    | "invocation_directory"
    | "invocation_directory_native"
    | "is_dependency"
    | "just_executable"
    | "just_pid"
    | "just_version"
    | "justfile"
    | "justfile_directory"
    | "module_directory"
    | "module_file"
    | "module_path"
    | "num_cpus"
    | "num_jobs"
    | "os"
    | "os_family"
    | "recipe_name"
    | "runtime_directory"
    | "source_directory"
    | "source_file"
    | "uuid" => (0, Some(0))
    "env" | "join_list" | "split" | "style" => (1, Some(2))
    "append"
    | "choose"
    | "env_var_or_default"
    | "prepend"
    | "semver_matches"
    | "trim_end_match"
    | "trim_end_matches"
    | "trim_start_match"
    | "trim_start_matches" => (2, Some(2))
    "replace" | "replace_regex" => (3, Some(3))
    "join" => (2, None)
    "shell" => (1, None)
    _ => (1, Some(1))
  }
}

///|
fn builtin_capabilities(name : String) -> Array[BuiltinCapability] {
  match name {
    "arch" | "os" | "os_family" => [Platform]
    "blake3_file" | "canonicalize" | "path_exists" | "read" | "sha256_file" =>
      [Context, FsRead]
    "env" | "env_var" | "env_var_or_default" => [Environment]
    "datetime" => [Context, Clock]
    "datetime_utc" => [Clock]
    "choose" | "uuid" => [Random]
    "shell" => [Context, Process]
    "which" | "require" => [Context, FsRead, Environment, Platform]
    "style" => [Terminal]
    "absolute_path"
    | "cache_directory"
    | "config_directory"
    | "config_local_directory"
    | "data_directory"
    | "data_local_directory"
    | "executable_directory"
    | "home_directory"
    | "invocation_directory"
    | "invocation_directory_native"
    | "is_dependency"
    | "just_executable"
    | "just_pid"
    | "just_version"
    | "justfile"
    | "justfile_directory"
    | "module_directory"
    | "module_file"
    | "module_path"
    | "num_cpus"
    | "num_jobs"
    | "recipe_name"
    | "runtime_directory"
    | "source_directory"
    | "source_file" => [Context]
    _ => []
  }
}

///|
fn builtin_aliases(name : String) -> Array[String] {
  let aliases : Array[String] = []
  if name.has_suffix("_directory_native") {
    aliases.push(
      name
      .view(end_offset=name.length() - "_directory_native".length())
      .to_owned() +
      "_dir_native",
    )
  } else if name.has_suffix("_directory") {
    aliases.push(
      name.view(end_offset=name.length() - "_directory".length()).to_owned() +
      "_dir",
    )
  }
  aliases
}

///|
pub fn registry() -> ArrayView[BuiltinSpec] {
  names().map(fn(name) {
    let (min_arguments, max_arguments) = builtin_arity(name)
    let capabilities = builtin_capabilities(name)
    let purity = if capabilities.is_empty() { Pure } else { Effect }
    {
      name,
      purity,
      min_arguments,
      max_arguments,
      aliases: builtin_aliases(name),
      capabilities,
      targets: [Native, Wasm1],
      evidence: "just-1.57.0/" + name,
    }
  })
}

///|
pub fn is_effectful(name : String) -> Bool {
  match find(name) {
    Some(spec) => spec.purity() is Effect
    None => false
  }
}

///|
pub fn canonical_name(name : String) -> String {
  let compatibility = match name {
    "path_join" => "join"
    "stem" => "file_stem"
    "regex_matches" => "replace_regex"
    _ => name
  }
  if compatibility.has_suffix("_dir_native") {
    compatibility
    .view(end_offset=compatibility.length() - "_dir_native".length())
    .to_owned() +
    "_directory_native"
  } else if compatibility.has_suffix("_dir") {
    compatibility
    .view(end_offset=compatibility.length() - "_dir".length())
    .to_owned() +
    "_directory"
  } else {
    compatibility
  }
}

///|
pub fn find(name : String) -> BuiltinSpec? {
  let canonical = canonical_name(name)
  registry().iter().find_first(fn(spec) { spec.name() == canonical })
}

///|
fn one(name : String, arguments : Array[Value]) -> Value raise BuiltinError {
  if arguments.length() != 1 {
    raise Arity(name~, expected="1", actual=arguments.length())
  }
  arguments[0]
}

///|
fn two(
  name : String,
  arguments : Array[Value],
) -> (Value, Value) raise BuiltinError {
  if arguments.length() != 2 {
    raise Arity(name~, expected="2", actual=arguments.length())
  }
  (arguments[0], arguments[1])
}

///|
fn string_argument(name : String, value : Value) -> String raise BuiltinError {
  match value.as_string() {
    Some(value) => value
    None => raise Type(name~, expected="string", actual=value)
  }
}

///|
fn lower_ascii(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character.is_ascii_uppercase() {
      builder.write_char((character.to_int() + 32).to_char().unwrap())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn upper_ascii(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character.is_ascii_lowercase() {
      builder.write_char((character.to_int() - 32).to_char().unwrap())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
