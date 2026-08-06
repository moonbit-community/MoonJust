///|
fn string_kind_key(kind : StringKind) -> String {
  match kind {
    Raw => "raw"
    Cooked => "cooked"
    Backtick => "backtick"
    TripleRaw => "triple-raw"
    TripleCooked => "triple-cooked"
  }
}

///|
fn literal_key(literal : StringLiteral) -> String {
  string_kind_key(literal.kind()) + "(" + literal.cooked() + ")"
}

///|
fn unary_key(operator : UnaryOperator) -> String {
  match operator {
    Not => "not"
  }
}

///|
fn binary_key(operator : BinaryOperator) -> String {
  match operator {
    Or => "or"
    And => "and"
    Equal => "equal"
    NotEqual => "not-equal"
    RegexMatch => "regex-match"
    RegexNotMatch => "regex-not-match"
    ListConcat => "list-concat"
    Concat => "concat"
    Join => "join"
  }
}

///|
/// A span-free semantic fingerprint used by formatter and differential tests.
/// Raw spelling and source locations are deliberately excluded; cooked literal
/// values, node kinds, ordering, and all semantic flags remain included.
pub fn Expression::semantic_key(self : Expression) -> String {
  match self {
    String(value) => "string:" + literal_key(value)
    Backtick(value) => "backtick:" + literal_key(value)
    Boolean(value~, ..) => "bool:" + value.to_string()
    Variable(name~, ..) => "var:" + name
    Call(name~, arguments~, ..) =>
      "call:" +
      name +
      "[" +
      arguments.map(Expression::semantic_key).join(",") +
      "]"
    List(elements~, ..) =>
      "list:[" + elements.map(Expression::semantic_key).join(",") + "]"
    Unary(operator~, operand~, ..) =>
      "unary:" + unary_key(operator) + "(" + operand.semantic_key() + ")"
    Binary(operator~, lhs~, rhs~, ..) =>
      "binary:" +
      binary_key(operator) +
      "(" +
      lhs.semantic_key() +
      "," +
      rhs.semantic_key() +
      ")"
    Conditional(condition~, then_branch~, else_branch~, ..) =>
      "if(" +
      condition.semantic_key() +
      "," +
      then_branch.semantic_key() +
      "," +
      else_branch.map(Expression::semantic_key).unwrap_or("") +
      ")"
    Format(start~, parts~, ..) =>
      "format:" +
      literal_key(start) +
      "[" +
      parts
      .map(fn(part) {
        part.expression().semantic_key() + "=>" + literal_key(part.literal())
      })
      .join(",") +
      "]"
  }
}

///|
fn parameter_key(parameter : Parameter) -> String {
  parameter.name() +
  ":" +
  parameter.variadic().to_string() +
  ":" +
  parameter.exported().to_string() +
  ":" +
  parameter.default_value().map(Expression::semantic_key).unwrap_or("")
}

///|
fn dependency_key(dependency : Dependency) -> String {
  dependency.name() +
  ":" +
  dependency.starred().to_string() +
  ":[" +
  dependency.arguments().map(Expression::semantic_key).join(",") +
  "]"
}

///|
fn attribute_key(attribute : Attribute) -> String {
  attribute.name() +
  "(" +
  attribute
  .arguments()
  .map(fn(argument) {
    argument.key().unwrap_or("") +
    "=" +
    argument.value().map(Expression::semantic_key).unwrap_or("")
  })
  .join(",") +
  ")"
}

///|
fn recipe_line_key(line : RecipeLine) -> String {
  line
  .fragments()
  .map(fn(fragment) {
    match fragment {
      Text(text~, ..) => "text:" + text
      Interpolation(expression~, ..) => "expr:" + expression.semantic_key()
    }
  })
  .join("|")
}

///|
/// Return a span-free fingerprint for one AST item.
pub fn Item::semantic_key(self : Item) -> String {
  match self {
    Assignment(value) =>
      "assignment:" +
      value.name() +
      ":" +
      value.exported().to_string() +
      ":" +
      value.eager().to_string() +
      ":" +
      value.value().semantic_key()
    Alias(value) => "alias:" + value.name() + "=" + value.target()
    Setting(value) =>
      "setting:" +
      value.name() +
      "=" +
      value.value().map(Expression::semantic_key).unwrap_or("")
    Import(value) =>
      "import:" + value.optional().to_string() + ":" + literal_key(value.path())
    Module(value) =>
      "module:" +
      value.name() +
      ":" +
      value.optional().to_string() +
      ":" +
      value.path().map(literal_key).unwrap_or("")
    Attribute(value) => "attribute:" + attribute_key(value)
    Unexport(name~, ..) => "unexport:" + name
    Comment(text~, ..) => "comment:" + text
    Blank(_) => "blank"
    Recipe(value) =>
      "recipe:" +
      value.name() +
      ":" +
      value.quiet().to_string() +
      ":params[" +
      value.parameters().map(parameter_key).join(",") +
      "]:deps[" +
      value.dependencies().map(dependency_key).join(",") +
      "]:subseq[" +
      value.subsequent_dependencies().map(dependency_key).join(",") +
      "]:lines[" +
      value.lines().map(recipe_line_key).join(",") +
      "]:attrs[" +
      value.attributes().map(attribute_key).join(",") +
      "]"
  }
}

///|
/// Return a deterministic semantic fingerprint for an AST, ignoring spans.
pub fn Ast::semantic_key(self : Ast) -> String {
  self.items().map(Item::semantic_key).join("\n")
}
