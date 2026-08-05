///|
/// Best-effort parser output for editor and diagnostic tooling.
pub struct ParseReport {
  ast : @syntax.Ast
  errors : Array[ParserError]
} derive(Debug)

///|
pub fn ParseReport::ast(self : ParseReport) -> @syntax.Ast {
  self.ast
}

///|
pub fn ParseReport::errors(self : ParseReport) -> ArrayView[ParserError] {
  self.errors[:]
}

///|
fn Parser::parse_next_recoverable_item(
  self : Parser,
) -> @syntax.Item raise ParserError {
  let attributes : Array[@syntax.Attribute] = []
  while self.peek_kind() == BracketL {
    for attribute in self.parse_attribute_group() {
      attributes.push(attribute)
    }
  }
  let item = self.parse_item(attributes)
  match item {
    Recipe(_) => ()
    _ => self.consume_line_end()
  }
  item
}

///|
fn Parser::recover_to_item_boundary(self : Parser) -> Unit {
  while self.peek_kind() != Eol &&
        self.peek_kind() != Dedent &&
        self.peek_kind() != Eof {
    self.advance() |> ignore
  }
  self.accept(Eol) |> ignore
  while self.accept(Dedent) is Some(_) {

  }
  self.depth = 0
}

///|
fn Parser::parse_ast_recovering(self : Parser) -> ParseReport {
  self.accept(ByteOrderMark) |> ignore
  let items : Array[@syntax.Item] = []
  let errors : Array[ParserError] = []
  while self.peek_kind() != Eof {
    if self.peek_kind() == Eol {
      let token = self.advance()
      items.push(Blank(span=token.span()))
      continue
    }
    match self.accept(Comment) {
      Some(comment) => {
        items.push(Comment(text=self.lexeme(comment), span=comment.span()))
        self.accept(Eol) |> ignore
        continue
      }
      None => ()
    }
    try self.parse_next_recoverable_item() catch {
      error => {
        errors.push(error)
        self.recover_to_item_boundary()
      }
    } noraise {
      item => items.push(item)
    }
  }
  {
    ast: @syntax.Ast::new(self.source.id(), items, self.source.full_span()),
    errors,
  }
}

///|
/// Parse a complete source while recovering at top-level line boundaries.
/// Lexer failures still abort because no trustworthy token boundary exists.
pub fn parse_recovering(
  source : @source.Source,
  limits? : ParserLimits = ParserLimits::default(),
) -> ParseReport raise ParserError {
  let stream = @lexer.lex(source) catch { error => raise LexerFailure(error) }
  Parser::new(source, stream, limits).parse_ast_recovering()
}
