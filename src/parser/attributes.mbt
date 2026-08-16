///|
/// Return the complete stable attribute inventory from `just 1.57.0`.
pub fn attribute_names() -> ArrayView[String] {
  [
    "android", "arg", "cache", "confirm", "continue", "default", "doc", "dragonfly",
    "env", "exit-message", "extension", "freebsd", "group", "linux", "macos", "metadata",
    "netbsd", "no-cd", "no-exit-message", "no-quiet", "openbsd", "parallel", "positional-arguments",
    "private", "script", "shell", "unix", "windows", "working-directory",
  ][:]
}

///|
fn known_attribute(name : String) -> Bool {
  attribute_names().contains(name)
}

///|
fn attribute_arity_valid(
  name : String,
  positional : Int,
  keywords : Int,
) -> Bool {
  match name {
    "confirm" | "doc" => keywords == 0 && positional <= 1
    "continue" | "script" => keywords == 0
    "arg" => positional == 1 && keywords <= 9
    "cache" => positional == 0 && keywords <= 3
    "extension" | "group" | "working-directory" =>
      positional == 1 && keywords == 0
    "env" => positional == 2 && keywords == 0
    "metadata" => positional >= 1 && keywords == 0
    "android"
    | "default"
    | "dragonfly"
    | "exit-message"
    | "freebsd"
    | "linux"
    | "macos"
    | "netbsd"
    | "no-cd"
    | "no-exit-message"
    | "no-quiet"
    | "openbsd"
    | "parallel"
    | "positional-arguments"
    | "private"
    | "shell"
    | "unix"
    | "windows" => positional == 0 && keywords == 0
    _ => false
  }
}

///|
fn attribute_key_valid(attribute : String, key : String) -> Bool {
  match attribute {
    "arg" =>
      [
        "flag", "help", "long", "max", "min", "multiple", "pattern", "short", "value",
      ].contains(key)
    "cache" => ["extra", "inputs", "outputs"].contains(key)
    _ => false
  }
}

///|
fn attribute_requires_literal(name : String) -> Bool {
  match name {
    "arg" | "continue" | "extension" | "group" | "metadata" | "script" => true
    _ => false
  }
}

///|
fn Parser::parse_attribute_group(
  self : Parser,
) -> Array[@syntax.Attribute] raise ParserError {
  let result : Array[@syntax.Attribute] = []
  self.expect(BracketL) |> ignore
  if self.peek_kind() == BracketR {
    let found = self.peek()
    raise UnexpectedToken(
      expected="identifier",
      found=found.kind(),
      span=found.span(),
    )
  }
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
          match value {
            Variable(name=key, ..) if attribute_key_valid(name, key) =>
              arguments.push(
                @syntax.AttributeArgument::new(Some(key), None, value.span()),
              )
            _ =>
              arguments.push(
                @syntax.AttributeArgument::new(None, Some(value), value.span()),
              )
          }
        }
        if self.accept(Comma) is None {
          break
        }
      }
      self.expect(ParenR) |> ignore
    }
    let span = name_token.span()
    let mut positional = 0
    let mut keywords = 0
    for argument in arguments {
      match argument.key() {
        Some(key) => {
          keywords += 1
          if !attribute_key_valid(name, key) {
            raise UnknownAttributeKey(
              attribute=name,
              key~,
              span=argument.span(),
            )
          }
        }
        None => positional += 1
      }
      let requires_literal = name != "arg" &&
        attribute_requires_literal(name) &&
        (
          argument.key() is None ||
          argument.key() is Some("max" | "min") ||
          (
            argument.key() is Some("long" | "short") &&
            argument.value() is Some(_)
          )
        )
      if requires_literal && !(argument.value() is Some(String(_))) {
        raise InvalidAttributeArgument(name~, span=argument.span())
      }
      if name != "arg" {
        match argument.key() {
          Some("flag" | "multiple") if argument.value() is Some(_) =>
            raise InvalidAttributeArgument(name~, span=argument.span())
          Some(key) if key != "flag" &&
            key != "multiple" &&
            key != "long" &&
            key != "short" &&
            argument.value() is None =>
            raise InvalidAttributeArgument(name~, span=argument.span())
          _ => ()
        }
      }
    }
    if arguments.length() > 32 ||
      !attribute_arity_valid(name, positional, keywords) {
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
