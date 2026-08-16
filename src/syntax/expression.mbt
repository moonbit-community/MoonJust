///|
/// A string literal after parser-owned escape validation.
pub(all) enum StringKind {
  Raw
  Cooked
  Backtick
  TripleRaw
  TripleCooked
} derive(Eq, Debug)

///|
pub(all) struct StringLiteral {
  raw : String
  cooked : String
  kind : StringKind
  span : @source.Span
  shell_expanded : Bool
} derive(Eq, Debug)

///|
pub fn StringLiteral::new(
  raw : String,
  cooked : String,
  kind : StringKind,
  span : @source.Span,
  shell_expanded? : Bool = false,
) -> StringLiteral {
  { raw, cooked, kind, span, shell_expanded }
}

///|
pub fn StringLiteral::raw(self : StringLiteral) -> String {
  self.raw
}

///|
pub fn StringLiteral::cooked(self : StringLiteral) -> String {
  self.cooked
}

///|
pub fn StringLiteral::kind(self : StringLiteral) -> StringKind {
  self.kind
}

///|
pub fn StringLiteral::span(self : StringLiteral) -> @source.Span {
  self.span
}

///|
pub fn StringLiteral::shell_expanded(self : StringLiteral) -> Bool {
  self.shell_expanded
}

///|
pub(all) enum UnaryOperator {
  Not
} derive(Eq, Debug)

///|
pub(all) enum BinaryOperator {
  Or
  And
  Equal
  NotEqual
  RegexMatch
  RegexNotMatch
  ListConcat
  Concat
  Join
} derive(Eq, Debug)

///|
pub(all) struct FormatPart {
  expression : Expression
  literal : StringLiteral
} derive(Eq, Debug)

///|
pub fn FormatPart::new(
  expression : Expression,
  literal : StringLiteral,
) -> FormatPart {
  { expression, literal }
}

///|
pub fn FormatPart::expression(self : FormatPart) -> Expression {
  self.expression
}

///|
pub fn FormatPart::literal(self : FormatPart) -> StringLiteral {
  self.literal
}

///|
/// Expressions retained by the parser. Every node carries the source span that
/// produced it so later diagnostics never have to reconstruct byte offsets.
pub(all) enum Expression {
  String(StringLiteral)
  Backtick(StringLiteral)
  Boolean(value~ : Bool, span~ : @source.Span)
  Variable(name~ : String, span~ : @source.Span)
  Call(name~ : String, arguments~ : Array[Expression], span~ : @source.Span)
  List(elements~ : Array[Expression], span~ : @source.Span)
  Parenthesized(expression~ : Expression, span~ : @source.Span)
  Unary(operator~ : UnaryOperator, operand~ : Expression, span~ : @source.Span)
  Binary(
    operator~ : BinaryOperator,
    lhs~ : Expression,
    rhs~ : Expression,
    span~ : @source.Span
  )
  Conditional(
    condition~ : Expression,
    then_branch~ : Expression,
    else_branch~ : Expression?,
    span~ : @source.Span
  )
  Format(
    start~ : StringLiteral,
    parts~ : Array[FormatPart],
    span~ : @source.Span
  )
} derive(Eq, Debug)

///|
pub fn Expression::span(self : Expression) -> @source.Span {
  match self {
    String(value) => value.span()
    Backtick(value) => value.span()
    Boolean(span~, ..) => span
    Variable(span~, ..) => span
    Call(span~, ..) => span
    List(span~, ..) => span
    Parenthesized(span~, ..) => span
    Unary(span~, ..) => span
    Binary(span~, ..) => span
    Conditional(span~, ..) => span
    Format(span~, ..) => span
  }
}

///|
pub fn Expression::kind(self : Expression) -> String {
  match self {
    String(_) => "string"
    Backtick(_) => "backtick"
    Boolean(_) => "boolean"
    Variable(_) => "variable"
    Call(_) => "call"
    List(_) => "list"
    Parenthesized(_) => "parenthesized"
    Unary(_) => "unary"
    Binary(_) => "binary"
    Conditional(_) => "conditional"
    Format(_) => "format"
  }
}
