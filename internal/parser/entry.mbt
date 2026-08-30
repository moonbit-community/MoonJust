///|
fn expression_line_end_expected(expression : @syntax.Expression) -> String {
  match expression {
    Binary(operator=Equal | NotEqual | RegexMatch | RegexNotMatch, ..) =>
      "'&&', '||', comment, end of file, end of line, '+', '++', or '/'"
    Conditional(_) =>
      "'&&', '!=', '!~', '||', comment, end of file, end of line, '==', or '=~'"
    _ =>
      "'&&', '!=', '!~', '||', comment, end of file, end of line, '==', '=~', '(', '+', '++', or '/'"
  }
}

///|
/// Parse a token stream into the target-independent syntax tree.
pub fn parse_tokens(
  source : @source.Source,
  stream : @lexer.TokenStream,
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Ast raise ParserError {
  Parser::new(source, stream, limits).parse_ast()
}

///|
/// Parse a token stream while resolving shell-expanded string literals from
/// the caller-provided host environment.
pub fn parse_tokens_with_environment(
  source : @source.Source,
  stream : @lexer.TokenStream,
  environment : ArrayView[(String, String)],
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Ast raise ParserError {
  Parser::new(source, stream, limits, environment~).parse_ast()
}

///|
/// Lex and parse one complete justfile source.
pub fn parse(
  source : @source.Source,
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Ast raise ParserError {
  let stream = @lexer.lex(source) catch { error => raise LexerFailure(error) }
  parse_tokens(source, stream, limits~)
}

///|
/// Lex and parse a justfile with the environment used by `x'…'` literals.
pub fn parse_with_environment(
  source : @source.Source,
  environment : ArrayView[(String, String)],
  limits? : ParserLimits = ParserLimits::default(),
) -> @syntax.Ast raise ParserError {
  let stream = @lexer.lex(source) catch { error => raise LexerFailure(error) }
  parse_tokens_with_environment(source, stream, environment, limits~)
}
