///|
/// Typed failures produced by grammar and parser-owned literal validation.
pub(all) suberror ParserError {
  LexerFailure(@lexer.LexerError)
  UnexpectedToken(
    expected~ : String,
    found~ : @lexer.TokenKind,
    span~ : @source.Span
  )
  InvalidEscapeSequence(character~ : String, span~ : @source.Span)
  InvalidUnicodeEscape(reason~ : String, span~ : @source.Span)
  UnknownSetting(name~ : String, span~ : @source.Span)
  UnknownAttribute(name~ : String, span~ : @source.Span)
  InvalidAttributeArity(name~ : String, span~ : @source.Span)
  InvalidAttributeArgument(name~ : String, span~ : @source.Span)
  UnknownAttributeKey(attribute~ : String, key~ : String, span~ : @source.Span)
  RecursionLimitExceeded(limit~ : Int, span~ : @source.Span)
  NodeLimitExceeded(limit~ : Int, span~ : @source.Span)
  ExtraneousInput(span~ : @source.Span)
} derive(Eq, Debug)

///|
pub fn ParserError::code(self : ParserError) -> String {
  match self {
    LexerFailure(_) => "MJ-PARSE-0000"
    UnexpectedToken(_) => "MJ-PARSE-0001"
    InvalidEscapeSequence(_) => "MJ-PARSE-0002"
    InvalidUnicodeEscape(_) => "MJ-PARSE-0003"
    UnknownSetting(_) => "MJ-PARSE-0004"
    UnknownAttribute(_) => "MJ-PARSE-0005"
    InvalidAttributeArity(_) => "MJ-PARSE-0006"
    InvalidAttributeArgument(_) => "MJ-PARSE-0007"
    UnknownAttributeKey(_) => "MJ-PARSE-0008"
    RecursionLimitExceeded(_) => "MJ-PARSE-0009"
    NodeLimitExceeded(_) => "MJ-PARSE-0010"
    ExtraneousInput(_) => "MJ-PARSE-0011"
  }
}

///|
pub fn ParserError::span(self : ParserError) -> @source.Span {
  match self {
    LexerFailure(error) => error.span()
    UnexpectedToken(span~, ..) => span
    InvalidEscapeSequence(span~, ..) => span
    InvalidUnicodeEscape(span~, ..) => span
    UnknownSetting(span~, ..) => span
    UnknownAttribute(span~, ..) => span
    InvalidAttributeArity(span~, ..) => span
    InvalidAttributeArgument(span~, ..) => span
    UnknownAttributeKey(span~, ..) => span
    RecursionLimitExceeded(span~, ..) => span
    NodeLimitExceeded(span~, ..) => span
    ExtraneousInput(span~) => span
  }
}

///|
pub fn ParserError::message(self : ParserError) -> String {
  match self {
    LexerFailure(error) => error.message()
    UnexpectedToken(expected~, found~, ..) =>
      "expected " + expected + ", but found `" + found.as_string() + "`"
    InvalidEscapeSequence(character~, ..) =>
      "`\\" + character + "` is not a valid escape sequence"
    InvalidUnicodeEscape(reason~, ..) => "invalid Unicode escape: " + reason
    UnknownSetting(name~, ..) => "unknown setting `" + name + "`"
    UnknownAttribute(name~, ..) => "unknown attribute `" + name + "`"
    InvalidAttributeArity(name~, ..) =>
      "invalid arguments for attribute `" + name + "`"
    InvalidAttributeArgument(name~, ..) =>
      "attribute `" + name + "` requires a string literal argument"
    UnknownAttributeKey(attribute~, key~, ..) =>
      "unknown key `" + key + "` for attribute `" + attribute + "`"
    RecursionLimitExceeded(limit~, ..) =>
      "parser recursion limit " + limit.to_string() + " exceeded"
    NodeLimitExceeded(limit~, ..) =>
      "parser node limit " + limit.to_string() + " exceeded"
    ExtraneousInput(_) => "unexpected input after expression"
  }
}

///|
pub fn ParserError::to_diagnostic(
  self : ParserError,
) -> @diagnostic.Diagnostic raise @diagnostic.DiagnosticError {
  @diagnostic.Diagnostic::new(
    self.code(),
    Error,
    self.message(),
    self.span(),
    "syntax error",
  )
}
