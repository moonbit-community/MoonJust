///|
fn lexer_behavior_exercises() -> Unit raise {
  let span = @source.Span::new(@source.SourceId::new(9500), 0, 1)
  let kinds : Array[@lexer.TokenKind] = [
    AmpersandAmpersand,
    Asterisk,
    At,
    Backtick,
    Bang,
    BangEquals,
    BangTilde,
    BarBar,
    BraceL,
    BraceR,
    BracketL,
    BracketR,
    ByteOrderMark,
    Colon,
    ColonColon,
    ColonEquals,
    Comma,
    Comment,
    Dedent,
    Dollar,
    Eof,
    Eol,
    Equals,
    EqualsEquals,
    EqualsTilde,
    FormatStringContinue,
    FormatStringEnd,
    FormatStringStart,
    Identifier,
    Indent,
    InterpolationEnd,
    InterpolationStart,
    ParenL,
    ParenR,
    Plus,
    PlusPlus,
    QuestionMark,
    Slash,
    StringToken,
    Text,
    Unspecified,
    Whitespace,
  ]
  for kind in kinds {
    assert_true(kind.as_string() != "")
    let token = @lexer.Token::new(kind, span)
    assert_eq(token.kind(), kind)
    let _ = token.is_synthetic()
  }
  let keywords : Array[@lexer.Keyword] = [
    Alias,
    AllowDuplicateRecipes,
    AllowDuplicateVariables,
    Assert,
    DefaultList,
    DefaultScript,
    DotenvCommand,
    DotenvFilename,
    DotenvLoad,
    DotenvOverride,
    DotenvPath,
    DotenvRequired,
    Eager,
    Else,
    Export,
    F,
    Fallback,
    False,
    Guards,
    If,
    IgnoreComments,
    Import,
    Indentation,
    Lazy,
    Lists,
    MinimumVersion,
    Mod,
    NoCd,
    NoExitMessage,
    PositionalArguments,
    Quiet,
    ScriptInterpreter,
    Set,
    Shell,
    Tempdir,
    True,
    Unexport,
    Unstable,
    WindowsPowershell,
    WindowsShell,
    WorkingDirectory,
    X,
  ]
  for keyword in keywords {
    let text = keyword.lexeme()
    assert_eq(@lexer.Keyword::from_lexeme(text), Some(keyword))
  }
  assert_true(@lexer.Keyword::from_lexeme("unknown") is None)
  let errors : Array[@lexer.LexerError] = [
    UnknownStartOfToken(start="\u{200B}", span~),
    UnexpectedEndOfToken(expected=")", span~),
    UnexpectedCharacter(expected="=", found="?", span~),
    InvalidEscapeSequence(character="q", span~),
    EscapeEndOfFile(span~),
    UnpairedCarriageReturn(span~),
    UnexpectedClosingDelimiter(close=Paren, span~),
    MismatchedClosingDelimiter(open=Brace, close=Bracket, open_line=3, span~),
    UnterminatedString(span~),
    UnterminatedBacktick(span~),
    UnterminatedInterpolation(span~),
    MixedLeadingWhitespace(whitespace=" \t", span~),
    InconsistentLeadingWhitespace(expected="  ", found="\t", span~),
    SourceLimitExceeded(length=10, limit=5, span~),
    TokenLimitExceeded(limit=5, span~),
    NestingLimitExceeded(limit=2, span~),
  ]
  for error in errors {
    assert_true(error.code().has_prefix("MJ-LEX-"))
    assert_eq(error.span(), span)
    let diagnostic = try! error.to_diagnostic()
    assert_eq(diagnostic.code(), error.code())
  }
  for value in [(-1, 10, 10), (10, -1, 10), (10, 10, -1)] {
    try @lexer.LexerLimits::new(value.0, value.1, value.2) catch {
      InvalidLexerLimit(..) => ()
    } noraise {
      _ => fail("expected invalid lexer limit")
    }
  }
}
