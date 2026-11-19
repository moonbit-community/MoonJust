///|
/// Path rules to apply independently of the current host platform.
#derive(Eq, Hash, Debug)
pub(all) enum PathFlavor {
  Unix
  Windows
}

///|
pub fn PathFlavor::separator(self : PathFlavor) -> Char {
  match self {
    Unix => '/'
    Windows => '\\'
  }
}

///|
priv enum PathRoot {
  Relative
  UnixRoot
  WindowsRoot
  WindowsDrive(String, Bool)
  WindowsPrefix(String)
}

///|
priv struct ParsedPath {
  root : PathRoot
  components : Array[String]
}

///|
/// A normalized lexical path with explicit Unix or Windows semantics.
#derive(Eq, Hash, Debug)
pub struct PathValue {
  value : String
  flavor : PathFlavor
}

///|
fn canonical_separators(raw : String, flavor : PathFlavor) -> String {
  let builder = StringBuilder()
  for character in raw {
    if flavor == Windows && (character == '/' || character == '\\') {
      builder.write_char('\\')
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn collect_nonempty(value : String, separator : StringView) -> Array[String] {
  let result : Array[String] = []
  for part in value.split(separator) {
    if !part.is_empty() {
      result.push("\{part}")
    }
  }
  result
}

///|
fn chars_after(value : String, count : Int32) -> String {
  let builder = StringBuilder()
  let mut index = 0
  for character in value {
    if index >= count {
      builder.write_char(character)
    }
    index += 1
  }
  builder.to_string()
}

///|
fn normalize_components(
  raw : ArrayView[String],
  rooted : Bool,
) -> Array[String] {
  let normalized : Array[String] = []
  for component in raw {
    if component == "" || component == "." {
      continue
    }
    if component == ".." {
      match normalized.last() {
        Some(previous) if previous != ".." => normalized.pop() |> ignore
        _ if !rooted => normalized.push(component)
        _ => ()
      }
    } else {
      normalized.push(component)
    }
  }
  normalized
}

///|
fn parse_unix(value : String) -> ParsedPath {
  let rooted = value.has_prefix("/")
  let root = if rooted { UnixRoot } else { Relative }
  {
    root,
    components: normalize_components(collect_nonempty(value, "/"), rooted),
  }
}

///|
fn parse_windows_prefix(parts : Array[String]) -> ParsedPath {
  guard !parts.is_empty() else { return { root: WindowsRoot, components: [], } }
  // An ordinary UNC prefix starts with the server and gains its share on
  // joining the next name. Extended UNC has two names after the namespace.
  let extended_unc = parts is ["?" | ".", name, ..] && name.to_upper() == "UNC"
  let start = if extended_unc { 2 } else { 1 }
  let prefix = parts[:start].to_owned()
  let prefix_len = if extended_unc { 4 } else { 2 }
  let mut end = start
  while end < parts.length() && prefix.length() < prefix_len {
    let name = parts[end]
    if name != "." && name != ".." {
      prefix.push(name)
    }
    end += 1
  }
  {
    root: WindowsPrefix("\\\\" + prefix.join("\\")),
    components: normalize_components(parts[end:], true),
  }
}

///|
fn parse_windows(value : String) -> ParsedPath {
  let characters = value.to_array()
  if value.has_prefix("\\\\") {
    parse_windows_prefix(collect_nonempty(value, "\\"))
  } else if characters.length() >= 2 &&
    characters[0].is_ascii_alphabetic() &&
    characters[1] == ':' {
    let drive = "\{characters[0]}:"
    let rooted = characters.length() >= 3 && characters[2] == '\\'
    let body = chars_after(value, if rooted { 3 } else { 2 })
    {
      root: WindowsDrive(drive, rooted),
      components: normalize_components(collect_nonempty(body, "\\"), rooted),
    }
  } else {
    let rooted = value.has_prefix("\\")
    {
      root: if rooted {
        WindowsRoot
      } else {
        Relative
      },
      components: normalize_components(collect_nonempty(value, "\\"), rooted),
    }
  }
}

///|
fn parse(value : String, flavor : PathFlavor) -> ParsedPath {
  match flavor {
    Unix => parse_unix(value)
    Windows => parse_windows(value)
  }
}

///|
fn joined_components(
  components : Array[String],
  separator : StringView,
) -> String {
  components[:].join(separator)
}

///|
fn format_parsed(parsed : ParsedPath, flavor : PathFlavor) -> String {
  let separator = match flavor {
    Unix => "/"
    Windows => "\\"
  }
  let body = joined_components(parsed.components, separator)
  match parsed.root {
    Relative => if body == "" { "." } else { body }
    UnixRoot => if body == "" { "/" } else { "/\{body}" }
    WindowsRoot => if body == "" { "\\" } else { "\\\{body}" }
    WindowsDrive(drive, false) => "\{drive}\{body}"
    WindowsDrive(drive, true) =>
      if body == "" {
        "\{drive}\\"
      } else {
        "\{drive}\\\{body}"
      }
    WindowsPrefix(root) => if body == "" { root } else { "\{root}\\\{body}" }
  }
}

///|
fn normalized(raw : String, flavor : PathFlavor) -> String {
  let canonical = canonical_separators(raw, flavor)
  format_parsed(parse(canonical, flavor), flavor)
}

///|
/// Parse and normalize a lexical path without consulting the host OS.
pub fn PathValue::new(
  raw : String,
  flavor : PathFlavor,
) -> PathValue raise PathError {
  if raw.contains("\u{0000}") {
    raise NulByte
  }
  { value: normalized(raw, flavor), flavor, }
}

///|
pub fn PathValue::as_string(self : PathValue) -> String {
  self.value
}

///|
pub fn PathValue::flavor(self : PathValue) -> PathFlavor {
  self.flavor
}

///|
pub fn PathValue::clean(self : PathValue) -> PathValue {
  self
}

///|
pub fn PathValue::is_absolute(self : PathValue) -> Bool {
  match parse(self.value, self.flavor).root {
    UnixRoot | WindowsRoot | WindowsDrive(_, true) | WindowsPrefix(_) => true
    Relative | WindowsDrive(_, false) => false
  }
}

///|
fn compose_raw(base : PathValue, child : String) -> String {
  match parse(child, base.flavor).root {
    UnixRoot | WindowsPrefix(_) | WindowsDrive(_, _) => child
    WindowsRoot =>
      match parse(base.value, base.flavor).root {
        WindowsDrive(drive, _) => drive + child
        WindowsPrefix(prefix) => prefix + child
        _ => child
      }
    Relative =>
      if child == "." || child.is_empty() {
        base.value
      } else if base.value == "." {
        child
      } else {
        let separator = base.flavor.separator().to_string()
        if base.value.has_suffix(separator) {
          base.value + child
        } else {
          base.value + separator + child
        }
      }
  }
}

///|
/// Join two paths using their declared flavor.
pub fn PathValue::join(
  self : PathValue,
  child : PathValue,
) -> PathValue raise PathError {
  if self.flavor != child.flavor {
    raise FlavorMismatch(expected=self.flavor, actual=child.flavor)
  }
  PathValue::new(compose_raw(self, child.value), self.flavor)
}

///|
/// Resolve a source spelling against this base before normalizing its parents.
/// For example, a share introduced by the child becomes part of the UNC root.
pub fn PathValue::join_text(
  self : PathValue,
  child : String,
) -> PathValue raise PathError {
  PathValue::new(
    compose_raw(self, canonical_separators(child, self.flavor)),
    self.flavor,
  )
}

///|
/// Return the lexical parent, or `None` for a root or `.`.
pub fn PathValue::parent(self : PathValue) -> PathValue? {
  let parsed = parse(self.value, self.flavor)
  if parsed.components.is_empty() {
    return None
  }
  parsed.components.pop() |> ignore
  Some({ value: format_parsed(parsed, self.flavor), flavor: self.flavor, })
}

///|
/// Return the final path component.
pub fn PathValue::file_name(self : PathValue) -> String? {
  parse(self.value, self.flavor).components.last()
}

///|
/// Return the suffix after the last dot in the final component.
pub fn PathValue::extension(self : PathValue) -> String? {
  match self.file_name() {
    None => None
    Some(name) =>
      match name.rev_find(".") {
        Some(0) | None => None
        Some(index) => Some("\{name[index + 1:]}")
      }
  }
}

///|
/// Remove the final extension while preserving the path's flavor and root.
pub fn PathValue::without_extension(self : PathValue) -> PathValue {
  let parsed = parse(self.value, self.flavor)
  match parsed.components.last() {
    None => self
    Some(name) =>
      match name.rev_find(".") {
        Some(index) if index > 0 => {
          parsed.components[parsed.components.length() - 1] = "\{name[:index]}"
          { value: format_parsed(parsed, self.flavor), flavor: self.flavor, }
        }
        _ => self
      }
  }
}
