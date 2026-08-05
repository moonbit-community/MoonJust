///|
pub struct MarkdownLimits {
  max_lines : Int
  max_bytes : Int
} derive(Eq, Debug)

///|
pub fn MarkdownLimits::new(
  max_lines : Int,
  max_bytes : Int,
) -> MarkdownLimits raise MarkdownError {
  if max_lines <= 0 || max_bytes <= 0 {
    raise InvalidLimit
  }
  { max_lines, max_bytes }
}

///|
pub fn MarkdownLimits::default() -> MarkdownLimits {
  { max_lines: 1_000_000, max_bytes: 64 * 1024 * 1024 }
}

///|
pub(all) suberror MarkdownError {
  InvalidLimit
  LimitExceeded(limit~ : Int, span~ : @source.Span)
} derive(Eq, Debug)

///|
pub struct TangledSource {
  source : @source.Source
  selected_blocks : Int
} derive(Debug)

///|
pub fn TangledSource::source(self : TangledSource) -> @source.Source {
  self.source
}

///|
pub fn TangledSource::selected_blocks(self : TangledSource) -> Int {
  self.selected_blocks
}

///|
fn fence_open(line : String) -> (Char, Int, String)? {
  let chars = line.to_array()
  if chars.length() < 3 {
    return None
  }
  let character = chars[0]
  if character != '`' && character != '~' {
    return None
  }
  let mut count = 0
  while count < chars.length() && chars[count] == character {
    count += 1
  }
  if count < 3 {
    return None
  }
  let info = if count == chars.length() {
    ""
  } else {
    line[count:].trim().to_owned()
  }
  Some((character, count, info))
}

///|
fn fence_close(line : String, character : Char, minimum : Int) -> Bool {
  let chars = line.to_array()
  if chars.length() < minimum || chars[0] != character {
    return false
  }
  let mut count = 0
  while count < chars.length() && chars[count] == character {
    count += 1
  }
  if count < minimum {
    return false
  }
  for index in count..<chars.length() {
    if !chars[index].is_ascii_whitespace() {
      return false
    }
  }
  true
}

///|
fn first_info_token(info : String) -> String? {
  let trimmed = info.trim()
  if trimmed == "just" ||
    trimmed.has_prefix("just ") ||
    trimmed.has_prefix("just\t") {
    Some("just")
  } else {
    None
  }
}

///|
fn append_line(
  output : Array[Byte],
  source : @source.Source,
  line : Int,
  keep : Bool,
) -> Unit {
  let span = try! source.line_span(line)
  if keep {
    for byte in (try! source.slice_bytes(span)) {
      output.push(byte)
    }
  } else {
    for _ in 0..<span.length() {
      output.push(b' ')
    }
  }
  if line < source.line_count() {
    let next = try! source.line_start(line + 1)
    for byte in source.bytes()[span.end_byte():next] {
      output.push(byte)
    }
  }
}

///|
/// Extract top-level fenced `just` blocks while preserving source byte offsets.
/// Non-selected bytes become spaces, so a later parser can report locations in
/// the original Markdown file without a second source-map format.
pub fn tangle(
  source : @source.Source,
  limits? : MarkdownLimits = MarkdownLimits::default(),
) -> TangledSource raise MarkdownError {
  if source.length() > limits.max_bytes {
    raise LimitExceeded(limit=limits.max_bytes, span=source.full_span())
  }
  if source.line_count() > limits.max_lines {
    raise LimitExceeded(limit=limits.max_lines, span=source.full_span())
  }
  let output : Array[Byte] = []
  let mut fence_character : Char? = None
  let mut fence_length = 0
  let mut ignored_fence_character : Char? = None
  let mut ignored_fence_length = 0
  let mut selected = false
  let mut in_html_comment = false
  let mut selected_blocks = 0
  for line in 1..<=source.line_count() {
    let text = try! source.line_text(line)
    if in_html_comment {
      append_line(output, source, line, false)
      if text.contains("-->") {
        in_html_comment = false
      }
      continue
    }
    if text.contains("<!--") {
      append_line(output, source, line, false)
      if !text.contains("-->") {
        in_html_comment = true
      }
      continue
    }
    match ignored_fence_character {
      Some(character) => {
        if fence_close(text, character, ignored_fence_length) {
          ignored_fence_character = None
        }
        append_line(output, source, line, false)
      }
      None =>
        match fence_character {
          Some(character) =>
            if fence_close(text, character, fence_length) {
              append_line(output, source, line, false)
              fence_character = None
              selected = false
            } else {
              append_line(output, source, line, selected)
            }
          None =>
            match fence_open(text) {
              Some((character, length, info)) => {
                fence_character = Some(character)
                fence_length = length
                selected = first_info_token(info) == Some("just")
                if selected {
                  selected_blocks += 1
                }
                append_line(output, source, line, false)
              }
              None => {
                let trimmed = text.trim()
                if trimmed != text {
                  match fence_open(trimmed.to_owned()) {
                    Some((character, length, _)) => {
                      ignored_fence_character = Some(character)
                      ignored_fence_length = length
                    }
                    None => ()
                  }
                }
                append_line(output, source, line, false)
              }
            }
        }
    }
  }
  let tangled = @source.Source::from_bytes(
    source.id(),
    source.name(),
    Bytes::from_array(output),
  ) catch {
    _ => raise InvalidLimit
  }
  { source: tangled, selected_blocks }
}
