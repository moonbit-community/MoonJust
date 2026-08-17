///|
/// A stable, API-owned source diagnostic. Positions are one-based Unicode
/// scalar coordinates and ranges are half-open.
pub struct ApiDiagnostic {
  code : String
  message : String
  source_name : String
  start_line : Int?
  start_column : Int?
  end_line : Int?
  end_column : Int?
} derive(Debug)

///|
pub fn ApiDiagnostic::code(self : ApiDiagnostic) -> String {
  self.code
}

///|
pub fn ApiDiagnostic::message(self : ApiDiagnostic) -> String {
  self.message
}

///|
pub fn ApiDiagnostic::source_name(self : ApiDiagnostic) -> String {
  self.source_name
}

///|
pub fn ApiDiagnostic::start_line(self : ApiDiagnostic) -> Int? {
  self.start_line
}

///|
pub fn ApiDiagnostic::start_column(self : ApiDiagnostic) -> Int? {
  self.start_column
}

///|
pub fn ApiDiagnostic::end_line(self : ApiDiagnostic) -> Int? {
  self.end_line
}

///|
pub fn ApiDiagnostic::end_column(self : ApiDiagnostic) -> Int? {
  self.end_column
}

///|
pub(all) suberror ApiError {
  InvalidSource(Array[ApiDiagnostic])
} derive(Debug)

///|
fn diagnostic_from_span(
  source : @source.Source,
  code : String,
  message : String,
  span : @source.Span?,
) -> ApiDiagnostic {
  match span {
    None =>
      {
        code,
        message,
        source_name: source.name(),
        start_line: None,
        start_column: None,
        end_line: None,
        end_column: None,
      }
    Some(span) => {
      let start = source.locate(span.start_byte()) catch {
        _ =>
          return {
            code,
            message,
            source_name: source.name(),
            start_line: None,
            start_column: None,
            end_line: None,
            end_column: None,
          }
      }
      let end = source.locate(span.end_byte()) catch {
        _ =>
          return {
            code,
            message,
            source_name: source.name(),
            start_line: None,
            start_column: None,
            end_line: None,
            end_column: None,
          }
      }
      {
        code,
        message,
        source_name: source.name(),
        start_line: Some(start.line()),
        start_column: Some(start.scalar_column() + 1),
        end_line: Some(end.line()),
        end_column: Some(end.scalar_column() + 1),
      }
    }
  }
}

///|
fn compile_text(
  text : String,
  source_name : String,
) -> (@source.Source, @semantic.Compilation) raise ApiError {
  let source = @source.Source::from_text(
    @source.SourceId::new(1),
    source_name,
    text,
  )
  let compilation = @semantic.compile_source(source) catch {
    error =>
      raise InvalidSource([
        diagnostic_from_span(
          source,
          error.code(),
          error.message(),
          Some(error.span()),
        ),
      ])
  }
  (source, compilation)
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
/// Parse and perform same-file semantic validation without loading imports.
pub fn check_source(
  text : String,
  source_name? : String = "justfile",
) -> Unit raise ApiError {
  ignore(compile_text(text, source_name))
}

///|
/// Format one in-memory source buffer without filesystem access.
pub fn format_text(
  text : String,
  source_name? : String = "justfile",
) -> String raise ApiError {
  let source = @source.Source::from_text(
    @source.SourceId::new(1),
    source_name,
    text,
  )
  @formatter.format_source(source) catch {
    error =>
      raise InvalidSource([
        diagnostic_from_span(
          source,
          error.code(),
          error.message(),
          error.span(),
        ),
      ])
  }
}

///|
/// Return the public root recipe names shown by default `just --summary`.
pub fn recipe_names(
  text : String,
  source_name? : String = "justfile",
) -> Array[String] raise ApiError {
  let (_, compilation) = compile_text(text, source_name)
  let names : Array[String] = []
  for name in compilation.recipe_names() {
    match compilation.recipe_attributes(name) {
      Some(attributes) if !name.has_prefix("_") && !attributes.private() =>
        names.push(name)
      _ => ()
    }
  }
  names.sort_by(lexical_compare)
  names
}
