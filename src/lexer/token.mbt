///|
/// Token categories emitted by the `just` 1.57.0-compatible lexer.
pub(all) enum TokenKind {
  AmpersandAmpersand
  Asterisk
  At
  Backtick
  Bang
  BangEquals
  BangTilde
  BarBar
  BraceL
  BraceR
  BracketL
  BracketR
  ByteOrderMark
  Colon
  ColonColon
  ColonEquals
  Comma
  Comment
  Dedent
  Dollar
  Eof
  Eol
  Equals
  EqualsEquals
  EqualsTilde
  FormatStringContinue
  FormatStringEnd
  FormatStringStart
  Identifier
  Indent
  InterpolationEnd
  InterpolationStart
  ParenL
  ParenR
  Plus
  PlusPlus
  QuestionMark
  Slash
  StringToken
  Text
  Unspecified
  Whitespace
} derive(Eq, Compare, Hash, Debug)

///|
/// Return the stable source spelling used in diagnostics and snapshots.
pub fn TokenKind::as_string(self : TokenKind) -> String {
  match self {
    AmpersandAmpersand => "&&"
    Asterisk => "*"
    At => "@"
    Backtick => "backtick"
    Bang => "!"
    BangEquals => "!="
    BangTilde => "!~"
    BarBar => "||"
    BraceL => "{"
    BraceR => "}"
    BracketL => "["
    BracketR => "]"
    ByteOrderMark => "byte-order-mark"
    Colon => ":"
    ColonColon => "::"
    ColonEquals => ":="
    Comma => ","
    Comment => "comment"
    Dedent => "dedent"
    Dollar => "$"
    Eof => "end-of-file"
    Eol => "end-of-line"
    Equals => "="
    EqualsEquals => "=="
    EqualsTilde => "=~"
    FormatStringContinue => "format-string-continue"
    FormatStringEnd => "format-string-end"
    FormatStringStart => "format-string-start"
    Identifier => "identifier"
    Indent => "indent"
    InterpolationEnd => "interpolation-end"
    InterpolationStart => "interpolation-start"
    ParenL => "("
    ParenR => ")"
    Plus => "+"
    PlusPlus => "++"
    QuestionMark => "?"
    Slash => "/"
    StringToken => "string"
    Text => "text"
    Unspecified => "unspecified"
    Whitespace => "whitespace"
  }
}

///|
/// A token paired with its half-open UTF-8 byte span.
pub struct Token {
  kind : TokenKind
  span : @source.Span
} derive(Eq, Debug)

///|
/// Construct a token. This is public for parser fixtures and tooling adapters.
pub fn Token::new(kind : TokenKind, span : @source.Span) -> Token {
  { kind, span, }
}

///|
/// Return this token's category.
pub fn Token::kind(self : Token) -> TokenKind {
  self.kind
}

///|
/// Return this token's source span.
pub fn Token::span(self : Token) -> @source.Span {
  self.span
}

///|
/// Return whether this token is synthesized rather than consuming source.
pub fn Token::is_synthetic(self : Token) -> Bool {
  self.kind == Dedent || self.kind == Eof
}

///|
/// Decode the token's exact source lexeme.
pub fn Token::lexeme(
  self : Token,
  source : @source.Source,
) -> String raise @source.SourceError {
  source.slice_text(self.span)
}

///|
/// Immutable result of lexing one source.
pub struct TokenStream {
  source_id : @source.SourceId
  tokens : Array[Token]
} derive(Debug)

///|
/// Return the source identity associated with this stream.
pub fn TokenStream::source_id(self : TokenStream) -> @source.SourceId {
  self.source_id
}

///|
/// Borrow all tokens, including the final `Eof` token.
pub fn TokenStream::tokens(self : TokenStream) -> ArrayView[Token] {
  self.tokens[:]
}

///|
/// Return the number of tokens, including `Eof`.
pub fn TokenStream::length(self : TokenStream) -> Int {
  self.tokens.length()
}
