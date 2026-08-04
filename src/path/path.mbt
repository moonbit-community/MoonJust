///|
/// Path rules to apply independently of the current host platform.
pub(all) enum PathFlavor {
  Unix
  Windows
} derive(Eq, Hash, Debug)

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
  WindowsUnc(String, String)
}

///|
priv struct ParsedPath {
  root : PathRoot
  components : Array[String]
}

///|
/// A normalized lexical path with explicit Unix or Windows semantics.
pub struct PathValue {
  value : String
  flavor : PathFlavor
} derive(Eq, Hash, Debug)

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
fn chars_after(value : String, count : Int) -> String {
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
fn normalize_components(raw : Array[String], rooted : Bool) -> Array[String] {
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
fn parse_windows(value : String) -> ParsedPath {
  let characters = value.to_array()
  if value.has_prefix("\\\\") {
    let all = collect_nonempty(value, "\\")
    if all.length() >= 2 {
      let body : Array[String] = []
      for index, component in all {
        if index >= 2 {
          body.push(component)
        }
      }
      {
        root: WindowsUnc(all[0], all[1]),
        components: normalize_components(body, true),
      }
    } else {
      { root: WindowsRoot, components: normalize_components(all, true) }
    }
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
    WindowsUnc(server, share) => {
      let root = "\\\\\{server}\\\{share}"
      if body == "" {
        root
      } else {
        "\{root}\\\{body}"
      }
    }
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
  { value: normalized(raw, flavor), flavor }
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
    UnixRoot | WindowsRoot | WindowsDrive(_, true) | WindowsUnc(_, _) => true
    Relative | WindowsDrive(_, false) => false
  }
}

///|
fn compose_raw(base : PathValue, child : ParsedPath) -> String {
  let child_text = format_parsed(child, base.flavor)
  match child.root {
    UnixRoot | WindowsUnc(_, _) | WindowsDrive(_, _) => child_text
    WindowsRoot =>
      match parse(base.value, base.flavor).root {
        WindowsDrive(drive, _) => "\{drive}\{child_text}"
        WindowsUnc(server, share) => "\\\\\{server}\\\{share}\{child_text}"
        _ => child_text
      }
    Relative =>
      if child_text == "." {
        base.value
      } else if base.value == "." {
        child_text
      } else {
        let separator = match base.flavor {
          Unix => "/"
          Windows => "\\"
        }
        "\{base.value}\{separator}\{child_text}"
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
  PathValue::new(
    compose_raw(self, parse(child.value, child.flavor)),
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
  Some({ value: format_parsed(parsed, self.flavor), flavor: self.flavor })
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
        Some(index) => Some("\{name.view(start_offset=index + 1)}")
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
          parsed.components[parsed.components.length() - 1] = "\{name.view(end_offset=index)}"
          { value: format_parsed(parsed, self.flavor), flavor: self.flavor }
        }
        _ => self
      }
  }
}
