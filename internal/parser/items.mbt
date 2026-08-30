///|
fn Parser::parse_item(
  self : Parser,
  attributes : Array[@syntax.Attribute],
) -> @syntax.Item raise ParserError {
  let start = self.peek().span()
  if self.peek_kind() == At {
    self.advance() |> ignore
    return Recipe(self.parse_recipe(true, attributes, None))
  }
  let mut prefetched_name : (String, @lexer.Token)? = None
  let keyword = if self.peek_kind() == Identifier {
    let token = self.peek()
    let name = self.lexeme(token)
    prefetched_name = Some((name, token))
    @lexer.Keyword::from_lexeme(name)
  } else {
    None
  }
  match keyword {
    Some(Export) if self.peek_kind_at(2) == Some(ColonEquals) => {
      self.advance() |> ignore
      Assignment(self.parse_assignment(start, true, false, attributes))
    }
    Some(Eager) if self.peek_kind_at(2) == Some(ColonEquals) => {
      self.advance() |> ignore
      Assignment(self.parse_assignment(start, false, true, attributes))
    }
    _ if self.peek_kind_at(1) == Some(ColonEquals) =>
      Assignment(self.parse_assignment(start, false, false, attributes))
    _ if self.peek_kind_at(1) == Some(ParenL) =>
      Function(self.parse_function_definition(start, attributes))
    Some(Alias) if self.peek_kind_at(2) == Some(ColonEquals) =>
      Alias(self.parse_alias(start, attributes))
    Some(Set) => Setting(self.parse_setting(start))
    Some(Import) => Import(self.parse_import(start))
    Some(Mod) if self.module_declaration_ahead() =>
      Module(self.parse_module(start, attributes))
    Some(Unexport) if self.peek_kind_at(1) == Some(Identifier) &&
      (
        self.peek_kind_at(2) == Some(Eol) ||
        self.peek_kind_at(2) == Some(Comment) ||
        self.peek_kind_at(2) == Some(Eof)
      ) => {
      self.advance() |> ignore
      let (name, name_token) = self.expect_identifier()
      Unexport(name~, span=self.cover(start, name_token.span()))
    }
    _ => Recipe(self.parse_recipe(false, attributes, prefetched_name))
  }
}

///|
fn Parser::parse_ast(self : Parser) -> @syntax.Ast raise ParserError {
  self.accept(ByteOrderMark) |> ignore
  let items : Array[@syntax.Item] = []
  while self.peek_kind() != Eof {
    if self.peek_kind() == Eol {
      let token = self.advance()
      items.push(Blank(span=token.span()))
      continue
    }
    match self.accept(Comment) {
      Some(comment) => {
        items.push(Comment(text=self.lexeme(comment), span=comment.span()))
        self.consume_line_end()
        continue
      }
      None => ()
    }
    let attributes : Array[@syntax.Attribute] = []
    let mut attribute_start : @source.Span? = None
    while self.peek_kind() == BracketL {
      if attribute_start is None {
        attribute_start = Some(self.peek().span())
      }
      for attribute in self.parse_attribute_group() {
        attributes.push(attribute)
      }
    }
    if !attributes.is_empty() &&
      (self.peek_kind() == Comment || self.peek_kind() == Eol) {
      raise ExtraneousAttribute(span=attribute_start.unwrap())
    }
    if !attributes.is_empty() && self.peek_kind() == Eof {
      let found = self.peek()
      raise UnexpectedToken(
        expected="'@', '[', comment, end of line, or identifier",
        found=found.kind(),
        span=found.span(),
      )
    }
    if self.peek_kind() == Eof {
      break
    }
    if self.peek_kind() != At && self.peek_kind() != Identifier {
      let found = self.peek()
      raise UnexpectedToken(
        expected="'@', '[', comment, end of file, end of line, or identifier",
        found=found.kind(),
        span=found.span(),
      )
    }
    let item = self.parse_item(attributes)
    match item {
      Setting(_) | Import(_) | Unexport(_) =>
        for attribute in attributes {
          items.push(Attribute(attribute))
        }
      _ => ()
    }
    items.push(item)
    match item {
      Recipe(_) => ()
      _ => {
        match self.accept(Comment) {
          Some(comment) =>
            items.push(
              TrailingComment(text=self.lexeme(comment), span=comment.span()),
            )
          None => ()
        }
        let expected = match item {
          Assignment(value) => expression_line_end_expected(value.value())
          Function(value) => expression_line_end_expected(value.body())
          Setting(value) =>
            value
            .value()
            .map(expression_line_end_expected)
            .unwrap_or("end-of-line")
          _ => "end-of-line"
        }
        self.consume_line_end_expected(expected)
      }
    }
  }
  @syntax.Ast::new(self.source.id(), items, self.source.full_span())
}

///|
