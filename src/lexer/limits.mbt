///|
/// Resource budgets applied by lexical analysis.
pub struct LexerLimits {
  max_source_bytes : Int
  max_tokens : Int
  max_nesting : Int
} derive(Eq, Debug)

///|
/// Construct explicit non-negative lexer budgets.
pub fn LexerLimits::new(
  max_source_bytes : Int,
  max_tokens : Int,
  max_nesting : Int,
) -> LexerLimits raise LexerConfigurationError {
  if max_source_bytes < 0 {
    raise InvalidLexerLimit(name="max_source_bytes", value=max_source_bytes)
  }
  if max_tokens < 0 {
    raise InvalidLexerLimit(name="max_tokens", value=max_tokens)
  }
  if max_nesting < 0 {
    raise InvalidLexerLimit(name="max_nesting", value=max_nesting)
  }
  { max_source_bytes, max_tokens, max_nesting }
}

///|
/// Return production defaults suitable for untrusted justfiles.
pub fn LexerLimits::default() -> LexerLimits {
  { max_source_bytes: 16 * 1024 * 1024, max_tokens: 1000000, max_nesting: 1024 }
}

///|
/// Return the maximum accepted UTF-8 source length in bytes.
pub fn LexerLimits::max_source_bytes(self : LexerLimits) -> Int {
  self.max_source_bytes
}

///|
/// Return the maximum emitted token count, including synthetic tokens.
pub fn LexerLimits::max_tokens(self : LexerLimits) -> Int {
  self.max_tokens
}

///|
/// Return the combined indentation, delimiter, and interpolation depth limit.
pub fn LexerLimits::max_nesting(self : LexerLimits) -> Int {
  self.max_nesting
}

///|
/// Invalid lexer configuration supplied by an embedding host.
pub(all) suberror LexerConfigurationError {
  InvalidLexerLimit(name~ : String, value~ : Int)
} derive(Eq, Debug)
