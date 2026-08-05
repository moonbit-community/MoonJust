///|
fn known_attribute(name : String) -> Bool {
  match name {
    "android"
    | "arg"
    | "cache"
    | "confirm"
    | "continue"
    | "default"
    | "doc"
    | "dragonfly"
    | "env"
    | "exit-message"
    | "extension"
    | "freebsd"
    | "group"
    | "linux"
    | "macos"
    | "metadata"
    | "netbsd"
    | "no-cd"
    | "no-exit-message"
    | "no-quiet"
    | "openbsd"
    | "parallel"
    | "positional-arguments"
    | "private"
    | "script"
    | "shell"
    | "unix"
    | "windows"
    | "working-directory" => true
    _ => false
  }
}

///|
fn Parser::parse_attribute_group(
  self : Parser,
) -> Array[@syntax.Attribute] raise ParserError {
  let result : Array[@syntax.Attribute] = []
  self.expect(BracketL) |> ignore
  while self.peek_kind() != BracketR {
    let (name, name_token) = self.expect_identifier()
    if !known_attribute(name) {
      raise UnknownAttribute(name~, span=name_token.span())
    }
    let arguments : Array[@syntax.AttributeArgument] = []
    if self.accept(Colon) is Some(_) {
      let value = self.parse_expression_node()
      arguments.push(
        @syntax.AttributeArgument::new(None, Some(value), value.span()),
      )
    } else if self.accept(ParenL) is Some(_) {
      while self.peek_kind() != ParenR {
        let first = self.peek()
        if self.peek_kind_at(1) == Some(Equals) {
          let (key, _) = self.expect_identifier()
          self.expect(Equals) |> ignore
          let value = self.parse_expression_node()
          arguments.push(
            @syntax.AttributeArgument::new(
              Some(key),
              Some(value),
              self.cover(first.span(), value.span()),
            ),
          )
        } else {
          let value = self.parse_expression_node()
          arguments.push(
            @syntax.AttributeArgument::new(None, Some(value), value.span()),
          )
        }
        if self.accept(Comma) is None {
          break
        }
      }
      self.expect(ParenR) |> ignore
    }
    let span = name_token.span()
    if arguments.length() > 32 {
      raise InvalidAttributeArity(name~, span~)
    }
    result.push(@syntax.Attribute::new(name, arguments, span))
    if self.accept(Comma) is None {
      break
    }
  }
  self.expect(BracketR) |> ignore
  self.consume_line_end()
  result
}
