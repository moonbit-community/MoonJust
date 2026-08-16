///|
fn quote_attribute_argument(argument : @syntax.AttributeArgument) -> String {
  match argument.value() {
    Some(value) => expression_text(value)
    None => ""
  }
}

///|
fn expression_precedence(expression : @syntax.Expression) -> Int {
  match expression {
    Conditional(_) => 1
    Binary(operator=Or, ..) => 2
    Binary(operator=And, ..) => 3
    Binary(operator=Equal | NotEqual | RegexMatch | RegexNotMatch, ..) => 4
    Binary(operator=ListConcat | Concat | Join, ..) => 5
    Unary(_) => 6
    _ => 7
  }
}

///|
fn binary_text(operator : @syntax.BinaryOperator) -> String {
  match operator {
    Or => "||"
    And => "&&"
    Equal => "=="
    NotEqual => "!="
    RegexMatch => "=~"
    RegexNotMatch => "!~"
    ListConcat => "++"
    Concat => "+"
    Join => "/"
  }
}

///|
fn expression_text_with_parent(
  expression : @syntax.Expression,
  parent : Int,
) -> String {
  if expression is Parenthesized(expression=inner, ..) {
    return expression_text_with_parent(inner, parent)
  }
  let own = expression_precedence(expression)
  let text = match expression {
    String(value) => value.raw()
    Backtick(value) => value.raw()
    Boolean(value~, ..) => if value { "true" } else { "false" }
    Variable(name~, ..) => name
    Call(name~, arguments~, ..) =>
      name + "(" + arguments.map(expression_text).join(", ") + ")"
    List(elements~, ..) => "[" + elements.map(expression_text).join(", ") + "]"
    Parenthesized(_) => abort("parenthesized expressions are handled above")
    Unary(operator=Not, operand~, ..) =>
      "!" + expression_text_with_parent(operand, own)
    Binary(operator~, lhs~, rhs~, ..) =>
      expression_text_with_parent(lhs, own) +
      " " +
      binary_text(operator) +
      " " +
      expression_text_with_parent(
        rhs,
        match operator {
          Concat | ListConcat | And | Or => own
          Equal | NotEqual | RegexMatch | RegexNotMatch | Join => own + 1
        },
      )
    Conditional(condition~, then_branch~, else_branch~, ..) => {
      let base = "if " +
        expression_text(condition) +
        " { " +
        expression_text(then_branch) +
        " }"
      match else_branch {
        Some(Conditional(_) as otherwise) =>
          base + " else " + expression_text(otherwise)
        Some(otherwise) => base + " else { " + expression_text(otherwise) + " }"
        None => base
      }
    }
    Format(start~, parts~, ..) => {
      let builder = StringBuilder()
      builder.write_string("f")
      builder.write_string(start.raw())
      for part in parts {
        builder.write_string(expression_text(part.expression()))
        builder.write_string(part.literal().raw())
      }
      builder.to_string()
    }
  }
  if own < parent {
    "(" + text + ")"
  } else {
    text
  }
}

///|
fn expression_text(expression : @syntax.Expression) -> String {
  expression_text_with_parent(expression, 0)
}

///|
fn attribute_text(attribute : @syntax.Attribute) -> String {
  let arguments = attribute.arguments()
  if arguments.is_empty() {
    "[" + attribute.name() + "]"
  } else {
    let values = arguments
      .map(fn(argument) {
        match argument.key() {
          Some(key) =>
            match argument.value() {
              Some(_) => key + "=" + quote_attribute_argument(argument)
              None => key
            }
          None => quote_attribute_argument(argument)
        }
      })
      .join(", ")
    "[" + attribute.name() + "(" + values + ")]"
  }
}

///|
fn parameters_text(parameters : ArrayView[@syntax.Parameter]) -> String {
  let builder = StringBuilder()
  for index, parameter in parameters {
    if index > 0 {
      builder.write_string(" ")
    }
    if parameter.variadic() {
      builder.write_string(
        if parameter.variadic_minimum() == 0 {
          "*"
        } else {
          "+"
        },
      )
    }
    if parameter.exported() {
      builder.write_string("$")
    }
    builder.write_string(parameter.name())
    match parameter.default_value() {
      Some(value) => {
        builder.write_char('=')
        let text = expression_text(value)
        builder.write_string(
          match value {
            Binary(_) | Parenthesized(expression=Binary(_), ..) =>
              "(" + text + ")"
            _ => text
          },
        )
      }
      None => ()
    }
  }
  builder.to_string()
}

///|
fn dependency_text(dependency : @syntax.Dependency) -> String {
  let arguments : Array[String] = []
  for index, expression in dependency.arguments() {
    let prefix = if dependency.starred_arguments().contains(index) {
      "*"
    } else {
      ""
    }
    arguments.push(prefix + expression_text(expression))
  }
  let arguments = arguments.join(" ")
  if dependency.arguments().is_empty() {
    dependency.name()
  } else if dependency.starred() {
    "*(" + dependency.name() + " " + arguments + ")"
  } else {
    "(" + dependency.name() + " " + arguments + ")"
  }
}

///|
fn item_text(item : @syntax.Item, indentation : String) -> String {
  match item {
    Assignment(value) => {
      let attributes = value
        .attributes()
        .map(attribute_text)
        .map(fn(text) { text + "\n" })
        .join("")
      let prefix = if value.exported() {
        "export "
      } else if value.eager() {
        "eager "
      } else {
        ""
      }
      attributes +
      prefix +
      value.name() +
      " := " +
      (match value.value() {
        Parenthesized(expression=inner, ..) =>
          "(" + expression_text(inner) + ")"
        expression => expression_text(expression)
      })
    }
    Function(value) => {
      let attributes = value
        .attributes()
        .map(attribute_text)
        .map(fn(text) { text + "\n" })
        .join("")
      attributes +
      value.name() +
      "(" +
      value.parameters().map(fn(parameter) { parameter.name() }).join(", ") +
      ") := " +
      expression_text(value.body())
    }
    Alias(value) =>
      value
      .attributes()
      .map(attribute_text)
      .map(fn(text) { text + "\n" })
      .join("") +
      "alias " +
      value.name() +
      " := " +
      value.target()
    Setting(value) =>
      match value.value() {
        Some(Boolean(value=true, ..)) => "set " + value.name()
        Some(expression) =>
          "set " + value.name() + " := " + expression_text(expression)
        None => "set " + value.name()
      }
    Import(value) =>
      "import" +
      (if value.optional() { "?" } else { "" }) +
      " " +
      value.path().raw()
    Module(value) => {
      let path = value.path().map(fn(path) { " " + path.raw() }).unwrap_or("")
      let attributes = value
        .attributes()
        .map(attribute_text)
        .map(fn(text) { text + "\n" })
        .join("")
      attributes +
      "mod" +
      (if value.optional() { "?" } else { "" }) +
      " " +
      value.name() +
      path
    }
    Unexport(name~, ..) => "unexport " + name
    Comment(text~, ..) => text
    TrailingComment(text~, ..) => text
    Blank(_) => ""
    Attribute(value) => attribute_text(value)
    Recipe(value) => recipe_text(value, indentation)
  }
}

///|
fn recipe_text(value : @syntax.Recipe, indentation : String) -> String {
  let builder = StringBuilder()
  for attribute in value.attributes() {
    builder.write_string(attribute_text(attribute))
    builder.write_char('\n')
  }
  if value.quiet() {
    builder.write_string("@")
  }
  builder.write_string(value.name())
  let params = parameters_text(value.parameters())
  if !params.is_empty() {
    builder.write_char(' ')
    builder.write_string(params)
  }
  builder.write_char(':')
  let deps = value.dependencies().map(dependency_text).join(" ")
  if !deps.is_empty() {
    builder.write_char(' ')
    builder.write_string(deps)
  }
  let subsequent = value
    .subsequent_dependencies()
    .map(dependency_text)
    .join(" ")
  if !subsequent.is_empty() {
    builder.write_string(" && ")
    builder.write_string(subsequent)
  }
  if value.lines().is_empty() && value.trailing_comment() is Some(comment) {
    builder.write_char(' ')
    builder.write_string(comment)
  }
  let mut line_count = value.lines().length()
  while line_count > 0 && value.lines()[line_count - 1].fragments().is_empty() {
    line_count -= 1
  }
  for index in 0..<line_count {
    let line = value.lines()[index]
    builder.write_char('\n')
    builder.write_string(indentation)
    for fragment in line.fragments() {
      match fragment {
        Text(text~, ..) => builder.write_string(text)
        Interpolation(expression~, ..) => {
          builder.write_string("{{ ")
          builder.write_string(expression_text(expression))
          builder.write_string(" }}")
        }
      }
    }
  }
  builder.to_string()
}

///|
pub fn format_expression(expression : @syntax.Expression) -> String {
  expression_text(expression)
}
