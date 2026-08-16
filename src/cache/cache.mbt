///|
pub const FORMAT_VERSION : Int = 1

///|
pub const KEY_ALGORITHM : String = "moonjust-cache-key-v1+blake3"

///|
pub const MAX_MANIFEST_BYTES : Int = 256 * 1024

///|
pub const MAX_INPUTS : Int = 1024

///|
pub const MAX_OUTPUTS : Int = 1024

///|
pub(all) suberror CacheError {
  InvalidDigest(String)
  InvalidPath(String)
  DuplicatePath(String)
  TooManyInputs(Int)
  TooManyOutputs(Int)
  ManifestTooLarge(Int)
  MalformedManifest(String)
  UnsupportedVersion(Int)
  AlgorithmMismatch(String)
  KeyMismatch
  RecipeMismatch
  OutputMismatch
} derive(Eq, Debug)

///|
pub struct InputDigest {
  path : String
  digest : String
} derive(Eq, Debug)

///|
pub fn InputDigest::new(
  path : String,
  digest : String,
) -> InputDigest raise CacheError {
  validate_relative_path(path)
  validate_digest(digest)
  { path, digest }
}

///|
pub fn InputDigest::path(self : InputDigest) -> String {
  self.path
}

///|
pub fn InputDigest::digest(self : InputDigest) -> String {
  self.digest
}

///|
pub struct CacheKey {
  recipe : String
  body : String
  interpreter : String
  interpreter_arguments : Array[String]
  environment : Array[(String, String)]
  extension : String
  working_directory : String
  positional : Array[String]
  extra : String
  inputs : Array[InputDigest]
  outputs : Array[String]
} derive(Eq)

///|
/// Cache key material can contain commands, arguments, and secret environment
/// values. Structural diagnostics therefore expose only safe metadata.
pub impl Debug for CacheKey with fn to_repr(self) {
  Repr::record({
    "recipe": Repr(self.recipe),
    "body_bytes": Repr(@utf8.encode(self.body).length()),
    "interpreter": Repr(self.interpreter),
    "interpreter_argument_count": Repr(self.interpreter_arguments.length()),
    "environment_keys": Repr(self.environment.map(fn(entry) { entry.0 })),
    "extension": Repr(self.extension),
    "working_directory": Repr(self.working_directory),
    "positional_count": Repr(self.positional.length()),
    "extra_bytes": Repr(@utf8.encode(self.extra).length()),
    "input_count": Repr(self.inputs.length()),
    "output_count": Repr(self.outputs.length()),
  })
}

///|
fn lexical_compare(left : String, right : String) -> Int {
  let length = Int::min(left.length(), right.length())
  for index in 0..<length {
    let order = left.unsafe_get(index).compare(right.unsafe_get(index))
    if order != 0 {
      return order
    }
  }
  left.length().compare(right.length())
}

///|
fn input_compare(left : InputDigest, right : InputDigest) -> Int {
  lexical_compare(left.path(), right.path())
}

///|
fn environment_compare(
  left : (String, String),
  right : (String, String),
) -> Int {
  let key = lexical_compare(left.0, right.0)
  if key != 0 {
    key
  } else {
    lexical_compare(left.1, right.1)
  }
}

///|
fn validate_digest(digest : String) -> Unit raise CacheError {
  if digest.length() != 64 {
    raise InvalidDigest(digest)
  }
  for character in digest {
    if !(character >= '0' && character <= '9') &&
      !(character >= 'a' && character <= 'f') {
      raise InvalidDigest(digest)
    }
  }
}

///|
pub fn validate_relative_path(path : String) -> Unit raise CacheError {
  if path.is_empty() || path.length() > 4096 {
    raise InvalidPath(path)
  }
  if path.has_prefix("/") || path.has_prefix("\\") || path.contains("\\") {
    raise InvalidPath(path)
  }
  let characters = path.to_array()
  if characters.length() >= 2 &&
    characters[0].is_ascii_alphabetic() &&
    characters[1] == ':' {
    raise InvalidPath(path)
  }
  for character in characters {
    let code = character.to_int()
    if code < 32 || code == 127 {
      raise InvalidPath(path)
    }
  }
  for segment in path.split("/") {
    if segment.is_empty() || segment == "." || segment == ".." {
      raise InvalidPath(path)
    }
  }
}

///|
fn normalize_outputs(
  outputs : ArrayView[String],
) -> Array[String] raise CacheError {
  if outputs.length() > MAX_OUTPUTS {
    raise TooManyOutputs(outputs.length())
  }
  let result = outputs.to_owned()
  result.sort_by(lexical_compare)
  let mut previous : String? = None
  for path in result {
    validate_relative_path(path)
    if previous == Some(path) {
      raise DuplicatePath(path)
    }
    previous = Some(path)
  }
  result
}

///|
fn normalize_inputs(
  inputs : ArrayView[InputDigest],
) -> Array[InputDigest] raise CacheError {
  if inputs.length() > MAX_INPUTS {
    raise TooManyInputs(inputs.length())
  }
  let result = inputs.to_owned()
  result.sort_by(input_compare)
  let mut previous : String? = None
  for input in result {
    validate_relative_path(input.path())
    validate_digest(input.digest())
    if previous == Some(input.path()) {
      raise DuplicatePath(input.path())
    }
    previous = Some(input.path())
  }
  result
}

///|
pub fn CacheKey::new(
  recipe : String,
  body : String,
  interpreter : String,
  interpreter_arguments? : Array[String] = [],
  environment? : Array[(String, String)] = [],
  extension? : String = "",
  working_directory? : String = "",
  positional? : Array[String] = [],
  extra? : String = "",
  inputs? : Array[InputDigest] = [],
  outputs? : Array[String] = [],
) -> CacheKey raise CacheError {
  let environment = environment.copy()
  environment.sort_by(environment_compare)
  let mut previous : String? = None
  for entry in environment {
    if previous == Some(entry.0) {
      raise DuplicatePath(entry.0)
    }
    previous = Some(entry.0)
  }
  {
    recipe,
    body,
    interpreter,
    interpreter_arguments: interpreter_arguments.copy(),
    environment,
    extension,
    working_directory,
    positional: positional.copy(),
    extra,
    inputs: normalize_inputs(inputs),
    outputs: normalize_outputs(outputs),
  }
}

///|
pub fn CacheKey::recipe(self : CacheKey) -> String {
  self.recipe
}

///|
pub fn CacheKey::outputs(self : CacheKey) -> ArrayView[String] {
  self.outputs[:]
}

///|
fn append_component(
  builder : StringBuilder,
  name : String,
  value : String,
) -> Unit {
  builder.write_string(name.length().to_string())
  builder.write_char(':')
  builder.write_string(name)
  builder.write_char('=')
  builder.write_string(value.length().to_string())
  builder.write_char(':')
  builder.write_string(value)
  builder.write_char(';')
}

///|
fn append_strings(
  builder : StringBuilder,
  name : String,
  values : ArrayView[String],
) -> Unit {
  append_component(builder, name + "-count", values.length().to_string())
  for value in values {
    append_component(builder, name, value)
  }
}

///|
pub fn CacheKey::canonical(self : CacheKey) -> String {
  let builder = StringBuilder()
  append_component(builder, "version", FORMAT_VERSION.to_string())
  append_component(builder, "algorithm", KEY_ALGORITHM)
  append_component(builder, "recipe", self.recipe)
  append_component(builder, "body", self.body)
  append_component(builder, "interpreter", self.interpreter)
  append_strings(builder, "interpreter-argument", self.interpreter_arguments)
  append_component(
    builder,
    "environment-count",
    self.environment.length().to_string(),
  )
  for entry in self.environment {
    append_component(builder, "environment-name", entry.0)
    append_component(builder, "environment-value", entry.1)
  }
  append_component(builder, "extension", self.extension)
  append_component(builder, "working-directory", self.working_directory)
  append_strings(builder, "positional", self.positional)
  append_component(builder, "extra", self.extra)
  append_component(builder, "input-count", self.inputs.length().to_string())
  for input in self.inputs {
    append_component(builder, "input-path", input.path())
    append_component(builder, "input-digest", input.digest())
  }
  append_strings(builder, "output", self.outputs)
  builder.to_string()
}

///|
pub fn CacheKey::digest(self : CacheKey) -> String {
  @builtin.blake3_bytes(@utf8.encode(self.canonical()))
}

///|
/// Render the cache-key document emitted by just 1.57.0 for `-vv`.
pub fn CacheKey::debug_json(self : CacheKey) -> String {
  let body : Array[Json] = []
  let body_lines : Array[String] = []
  for line in self.body.split("\n") {
    body_lines.push(line.to_owned())
  }
  while body_lines.last() is Some("") {
    ignore(body_lines.pop())
  }
  for line in body_lines {
    body.push(Json::string(line))
  }
  let environment : Map[String, Json] = Map([])
  for entry in self.environment {
    environment[entry.0] = Json::string(entry.1)
  }
  let input_json : Json = if self.inputs.is_empty() {
    Json::null()
  } else {
    let values : Map[String, Json] = Map([])
    for input in self.inputs {
      values[input.path()] = Json::string(input.digest())
    }
    Json::object(values)
  }
  Json::object(
    Map([
      ("body", Json::array(body)),
      ("environment", Json::object(environment)),
      (
        "executor",
        Json::object(
          Map([
            ("type", Json::string("command")),
            ("command", Json::string(self.interpreter)),
            (
              "arguments",
              Json::array(self.interpreter_arguments.map(Json::string)),
            ),
          ]),
        ),
      ),
      (
        "extension",
        if self.extension.is_empty() {
          Json::null()
        } else {
          Json::string(self.extension)
        },
      ),
      (
        "extra",
        if self.extra.is_empty() {
          Json::null()
        } else {
          Json::string(self.extra)
        },
      ),
      ("inputs", input_json),
      (
        "positional",
        if self.positional.is_empty() {
          Json::null()
        } else {
          Json::array(self.positional.map(Json::string))
        },
      ),
      ("recipe", Json::string(self.recipe)),
      ("working_directory", Json::string(self.working_directory)),
    ]),
  ).stringify(indent=2)
}

///|
/// Incremental content hashing used by HostFs range readers without retaining
/// an entire input file in memory.
pub struct ContentHasher {
  inner : @builtin.Blake3Hasher
}

///|
pub fn ContentHasher::new() -> ContentHasher {
  { inner: @builtin.Blake3Hasher::new() }
}

///|
pub fn ContentHasher::update(self : ContentHasher, bytes : Bytes) -> Unit {
  self.inner.update(bytes)
}

///|
pub fn ContentHasher::finalize(self : ContentHasher) -> String {
  self.inner.finalize()
}

///|
pub struct CacheManifest {
  version : Int
  algorithm : String
  key : String
  recipe : String
  outputs : Array[String]
} derive(Eq, Debug)

///|
pub fn CacheManifest::new(
  key : String,
  recipe : String,
  outputs : ArrayView[String],
) -> CacheManifest raise CacheError {
  validate_digest(key)
  let manifest = {
    version: FORMAT_VERSION,
    algorithm: KEY_ALGORITHM,
    key,
    recipe,
    outputs: normalize_outputs(outputs),
  }
  let encoded_length = @utf8.encode(manifest.encode()).length()
  if encoded_length > MAX_MANIFEST_BYTES {
    raise ManifestTooLarge(encoded_length)
  }
  manifest
}

///|
pub fn CacheManifest::key(self : CacheManifest) -> String {
  self.key
}

///|
pub fn CacheManifest::recipe(self : CacheManifest) -> String {
  self.recipe
}

///|
pub fn CacheManifest::outputs(self : CacheManifest) -> ArrayView[String] {
  self.outputs[:]
}

///|
pub fn CacheManifest::encode(self : CacheManifest) -> String {
  Json::object(Map([("recipe", Json::string(self.recipe))])).stringify()
}

///|
fn manifest_string(
  fields : Map[String, Json],
  name : String,
) -> String raise CacheError {
  guard fields.get(name) is Some(String(value)) else {
    raise MalformedManifest("field `\{name}` must be a string")
  }
  value
}

///|
pub fn decode_manifest(text : String) -> CacheManifest raise CacheError {
  let encoded_length = @utf8.encode(text).length()
  if encoded_length > MAX_MANIFEST_BYTES {
    raise ManifestTooLarge(encoded_length)
  }
  let value = @json.parse(text[:]) catch {
    _ => raise MalformedManifest("invalid JSON")
  }
  guard value is Object(fields) else {
    raise MalformedManifest("manifest root must be an object")
  }
  if fields.length() == 1 {
    let recipe = manifest_string(fields, "recipe")
    return {
      version: FORMAT_VERSION,
      algorithm: KEY_ALGORITHM,
      key: "",
      recipe,
      outputs: [],
    }
  }
  if fields.length() != 5 {
    raise MalformedManifest("manifest fields do not match schema")
  }
  guard fields.get("version") is Some(Number(number, ..)) else {
    raise MalformedManifest("field `version` must be a number")
  }
  let version = number.to_int()
  if number != version.to_double() {
    raise MalformedManifest("field `version` must be an integer")
  }
  if version != FORMAT_VERSION {
    raise UnsupportedVersion(version)
  }
  let algorithm = manifest_string(fields, "algorithm")
  if algorithm != KEY_ALGORITHM {
    raise AlgorithmMismatch(algorithm)
  }
  let key = manifest_string(fields, "key")
  validate_digest(key)
  let recipe = manifest_string(fields, "recipe")
  guard fields.get("outputs") is Some(Array(values)) else {
    raise MalformedManifest("field `outputs` must be an array")
  }
  let outputs : Array[String] = []
  for value in values {
    guard value is String(path) else {
      raise MalformedManifest("output paths must be strings")
    }
    outputs.push(path)
  }
  { version, algorithm, key, recipe, outputs: normalize_outputs(outputs) }
}

///|
pub fn validate_manifest(
  text : String,
  expected_key : String,
  expected_recipe : String,
  expected_outputs : ArrayView[String],
) -> CacheManifest raise CacheError {
  validate_digest(expected_key)
  let manifest = decode_manifest(text)
  if !manifest.key.is_empty() && manifest.key != expected_key {
    raise KeyMismatch
  }
  if manifest.recipe != expected_recipe {
    raise RecipeMismatch
  }
  if !manifest.outputs.is_empty() &&
    manifest.outputs != normalize_outputs(expected_outputs) {
    raise OutputMismatch
  }
  CacheManifest::new(expected_key, expected_recipe, expected_outputs)
}
