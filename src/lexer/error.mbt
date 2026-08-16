///|
/// Delimiter categories tracked by the lexer.
pub(all) enum DelimiterKind {
  Brace
  Bracket
  Paren
  FormatString
} derive(Eq, Debug)

///|
/// Typed failures emitted by lexical analysis.
pub(all) suberror LexerError {
  UnknownStartOfToken(start~ : String, span~ : @source.Span)
  UnexpectedEndOfToken(expected~ : String, span~ : @source.Span)
  UnexpectedCharacter(expected~ : String, found~ : String, span~ : @source.Span)
  InvalidEscapeSequence(character~ : String, span~ : @source.Span)
  EscapeEndOfFile(span~ : @source.Span)
  UnpairedCarriageReturn(span~ : @source.Span)
  UnexpectedClosingDelimiter(close~ : DelimiterKind, span~ : @source.Span)
  MismatchedClosingDelimiter(
    open~ : DelimiterKind,
    close~ : DelimiterKind,
    open_line~ : Int,
    span~ : @source.Span
  )
  UnterminatedString(span~ : @source.Span)
  UnterminatedBacktick(span~ : @source.Span)
  UnterminatedInterpolation(span~ : @source.Span)
  MixedLeadingWhitespace(whitespace~ : String, span~ : @source.Span)
  InconsistentLeadingWhitespace(
    expected~ : String,
    found~ : String,
    span~ : @source.Span
  )
  SourceLimitExceeded(length~ : Int, limit~ : Int, span~ : @source.Span)
  TokenLimitExceeded(limit~ : Int, span~ : @source.Span)
  NestingLimitExceeded(limit~ : Int, span~ : @source.Span)
} derive(Eq, Debug)

///|
/// Return the stable diagnostic code for a lexical failure.
pub fn LexerError::code(self : LexerError) -> String {
  match self {
    UnknownStartOfToken(_) => "MJ-LEX-0001"
    UnexpectedEndOfToken(_) => "MJ-LEX-0002"
    UnexpectedCharacter(_) => "MJ-LEX-0003"
    InvalidEscapeSequence(_) => "MJ-LEX-0004"
    EscapeEndOfFile(_) => "MJ-LEX-0005"
    UnpairedCarriageReturn(_) => "MJ-LEX-0006"
    UnexpectedClosingDelimiter(_) => "MJ-LEX-0007"
    MismatchedClosingDelimiter(_) => "MJ-LEX-0008"
    UnterminatedString(_) => "MJ-LEX-0009"
    UnterminatedBacktick(_) => "MJ-LEX-0010"
    UnterminatedInterpolation(_) => "MJ-LEX-0011"
    MixedLeadingWhitespace(_) => "MJ-LEX-0012"
    InconsistentLeadingWhitespace(_) => "MJ-LEX-0013"
    SourceLimitExceeded(_) => "MJ-LEX-0014"
    TokenLimitExceeded(_) => "MJ-LEX-0015"
    NestingLimitExceeded(_) => "MJ-LEX-0016"
  }
}

///|
/// Return the primary span associated with a lexical failure.
pub fn LexerError::span(self : LexerError) -> @source.Span {
  match self {
    UnknownStartOfToken(span~, ..) => span
    UnexpectedEndOfToken(span~, ..) => span
    UnexpectedCharacter(span~, ..) => span
    InvalidEscapeSequence(span~, ..) => span
    EscapeEndOfFile(span~) => span
    UnpairedCarriageReturn(span~) => span
    UnexpectedClosingDelimiter(span~, ..) => span
    MismatchedClosingDelimiter(span~, ..) => span
    UnterminatedString(span~) => span
    UnterminatedBacktick(span~) => span
    UnterminatedInterpolation(span~) => span
    MixedLeadingWhitespace(span~, ..) => span
    InconsistentLeadingWhitespace(span~, ..) => span
    SourceLimitExceeded(span~, ..) => span
    TokenLimitExceeded(span~, ..) => span
    NestingLimitExceeded(span~, ..) => span
  }
}

///|
fn delimiter_text(delimiter : DelimiterKind) -> String {
  match delimiter {
    Brace => "brace"
    Bracket => "bracket"
    Paren => "parenthesis"
    FormatString => "format string"
  }
}

///|
fn visible_whitespace(whitespace : String) -> String {
  let builder = StringBuilder()
  for character in whitespace {
    builder.write_string(
      match character {
        '\t' => "␉"
        ' ' => "␠"
        other => other.to_string()
      },
    )
  }
  builder.to_string()
}

///|
/// Return a stable, color-free summary matching upstream terminology.
pub fn LexerError::message(self : LexerError) -> String {
  match self {
    UnknownStartOfToken(start~, ..) => "unknown start of token '\{start}'"
    UnexpectedEndOfToken(expected~, ..) =>
      "expected character `\{expected}` but found end-of-file"
    UnexpectedCharacter(expected~, found~, ..) =>
      "expected character `\{expected}` but found `\{found}`"
    InvalidEscapeSequence(character~, ..) =>
      "`\\\{character}` is not a valid escape sequence"
    EscapeEndOfFile(_) => "expected newline but found end-of-file"
    UnpairedCarriageReturn(_) => "unpaired carriage return"
    UnexpectedClosingDelimiter(close~, ..) =>
      "unexpected closing \{delimiter_text(close)}"
    MismatchedClosingDelimiter(open~, close~, open_line~, ..) =>
      "mismatched closing \{delimiter_text(close)}, expected \{delimiter_text(open)} opened on line \{open_line}"
    UnterminatedString(_) => "unterminated string"
    UnterminatedBacktick(_) => "unterminated backtick"
    UnterminatedInterpolation(_) => "unterminated interpolation"
    MixedLeadingWhitespace(whitespace~, ..) =>
      "found a mix of tabs and spaces in leading whitespace: `" +
      visible_whitespace(whitespace) +
      "`\nleading whitespace may consist of tabs or spaces, but not both"
    InconsistentLeadingWhitespace(expected~, found~, ..) =>
      "recipe line has inconsistent leading whitespace, started with `" +
      visible_whitespace(expected) +
      "` but found line with `" +
      visible_whitespace(found) +
      "`"
    SourceLimitExceeded(length~, limit~, ..) =>
      "source length \{length} exceeds lexer limit \{limit}"
    TokenLimitExceeded(limit~, ..) => "token count exceeds lexer limit \{limit}"
    NestingLimitExceeded(limit~, ..) =>
      "delimiter nesting exceeds lexer limit \{limit}"
  }
}

///|
/// Convert a lexical failure into the shared presentation-independent IR.
pub fn LexerError::to_diagnostic(
  self : LexerError,
) -> @diagnostic.Diagnostic raise @diagnostic.DiagnosticError {
  @diagnostic.Diagnostic::new(
    self.code(),
    Error,
    self.message(),
    self.span(),
    "lexical error",
  )
}
