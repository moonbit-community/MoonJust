///|
/// Typed failures produced by grammar and parser-owned literal validation.
pub(all) suberror ParserError {
  LexerFailure(@lexer.LexerError)
  UnexpectedToken(
    expected~ : String,
    found~ : @lexer.TokenKind,
    span~ : @source.Span
  )
  UnexpectedConstruct(expected~ : String, found~ : String, span~ : @source.Span)
  InvalidEscapeSequence(character~ : String, span~ : @source.Span)
  InvalidUnicodeEscape(reason~ : String, span~ : @source.Span)
  BacktickShebang(span~ : @source.Span)
  ShellExpansion(variable~ : String, span~ : @source.Span)
  UnknownSetting(name~ : String, span~ : @source.Span)
  InvalidSettingValue(name~ : String, span~ : @source.Span)
  UnknownAttribute(name~ : String, span~ : @source.Span)
  InvalidAttributeArity(name~ : String, actual~ : Int, span~ : @source.Span)
  InvalidAttributeArgument(name~ : String, span~ : @source.Span)
  PositionalAttributeAfterKeyword(span~ : @source.Span)
  UnknownAttributeKey(attribute~ : String, key~ : String, span~ : @source.Span)
  ExtraneousAttribute(span~ : @source.Span)
  RecursionLimitExceeded(limit~ : Int, span~ : @source.Span)
  NodeLimitExceeded(limit~ : Int, span~ : @source.Span)
  ExtraneousInput(span~ : @source.Span)
} derive(Eq, Debug)

///|
pub fn ParserError::code(self : ParserError) -> String {
  match self {
    LexerFailure(_) => "MJ-PARSE-0000"
    UnexpectedToken(_) | UnexpectedConstruct(_) => "MJ-PARSE-0001"
    InvalidEscapeSequence(_) => "MJ-PARSE-0002"
    InvalidUnicodeEscape(_) => "MJ-PARSE-0003"
    BacktickShebang(_) => "MJ-PARSE-0013"
    ShellExpansion(_) => "MJ-PARSE-0014"
    UnknownSetting(_) => "MJ-PARSE-0004"
    InvalidSettingValue(_) => "MJ-PARSE-0005"
    UnknownAttribute(_) => "MJ-PARSE-0006"
    InvalidAttributeArity(_) => "MJ-PARSE-0007"
    InvalidAttributeArgument(_) => "MJ-PARSE-0008"
    PositionalAttributeAfterKeyword(_) => "MJ-PARSE-0008"
    UnknownAttributeKey(_) => "MJ-PARSE-0009"
    ExtraneousAttribute(_) => "MJ-PARSE-0015"
    RecursionLimitExceeded(_) => "MJ-PARSE-0010"
    NodeLimitExceeded(_) => "MJ-PARSE-0011"
    ExtraneousInput(_) => "MJ-PARSE-0012"
  }
}

///|
pub fn ParserError::span(self : ParserError) -> @source.Span {
  match self {
    LexerFailure(error) => error.span()
    UnexpectedToken(span~, ..) => span
    UnexpectedConstruct(span~, ..) => span
    InvalidEscapeSequence(span~, ..) => span
    InvalidUnicodeEscape(span~, ..) => span
    BacktickShebang(span~) => span
    ShellExpansion(span~, ..) => span
    UnknownSetting(span~, ..) => span
    InvalidSettingValue(span~, ..) => span
    UnknownAttribute(span~, ..) => span
    InvalidAttributeArity(span~, ..) => span
    InvalidAttributeArgument(span~, ..) => span
    PositionalAttributeAfterKeyword(span~) => span
    UnknownAttributeKey(span~, ..) => span
    ExtraneousAttribute(span~) => span
    RecursionLimitExceeded(span~, ..) => span
    NodeLimitExceeded(span~, ..) => span
    ExtraneousInput(span~) => span
  }
}

///|
pub fn ParserError::message(self : ParserError) -> String {
  match self {
    LexerFailure(error) => error.message()
    UnexpectedToken(expected~, found=Eof, ..) =>
      "expected " + expected + ", but found end of file"
    UnexpectedToken(expected~, found~, ..) =>
      "expected " + expected + ", but found " + found.diagnostic_name()
    UnexpectedConstruct(expected~, found~, ..) =>
      "expected " + expected + " but found " + found
    InvalidEscapeSequence(character~, ..) =>
      "`\\" + character + "` is not a valid escape sequence"
    InvalidUnicodeEscape(reason~, ..) => reason
    BacktickShebang(_) => "backticks may not start with `#!`"
    ShellExpansion(variable~, ..) =>
      "shell expansion failed: error looking key '" +
      variable +
      "' up: environment variable not found"
    UnknownSetting(name~, ..) => "unknown setting `" + name + "`"
    InvalidSettingValue(name~, ..) => "invalid value for setting `" + name + "`"
    UnknownAttribute(name~, ..) => "unknown attribute `" + name + "`"
    InvalidAttributeArity(name~, actual~, ..) => {
      let expected = match name {
        "confirm" | "doc" => "at most 1 argument"
        "metadata" => "at least 1 argument"
        "extension" | "group" | "working-directory" => "1 argument"
        "env" => "2 arguments"
        "arg" => "at least 1 argument"
        _ => "0 arguments"
      }
      "attribute `" +
      name +
      "` got " +
      actual.to_string() +
      (if actual == 1 { " argument" } else { " arguments" }) +
      " but takes " +
      expected
    }
    InvalidAttributeArgument(name~, ..) =>
      "attribute `" + name + "` requires a string literal argument"
    PositionalAttributeAfterKeyword(_) =>
      "positional attribute arguments cannot follow keyword attribute arguments"
    UnknownAttributeKey(attribute~, key~, ..) =>
      "unknown key `" + key + "` for `" + attribute + "` attribute"
    ExtraneousAttribute(_) => "extraneous attribute"
    RecursionLimitExceeded(_) => "parsing recursion depth exceeded"
    NodeLimitExceeded(limit~, ..) =>
      "parser node limit " + limit.to_string() + " exceeded"
    ExtraneousInput(_) => "unexpected input after expression"
  }
}

///|
fn @lexer.TokenKind::diagnostic_name(self : @lexer.TokenKind) -> String {
  match self {
    At
    | Asterisk
    | AmpersandAmpersand
    | Bang
    | BangEquals
    | BangTilde
    | BarBar
    | BraceL
    | BraceR
    | BracketL
    | BracketR
    | Colon
    | ColonColon
    | ColonEquals
    | Comma
    | Dollar
    | Equals
    | EqualsEquals
    | EqualsTilde
    | InterpolationEnd
    | InterpolationStart
    | ParenL
    | ParenR
    | Plus
    | PlusPlus
    | QuestionMark
    | Slash => "'" + self.as_string() + "'"
    ByteOrderMark => "byte order mark"
    Eol => "end of line"
    FormatStringContinue => "format string continue"
    FormatStringEnd => "format string end"
    FormatStringStart => "format string start"
    other => other.as_string()
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
    "",
  )
}
