///|
/// Conservatively classify expressions that require host-backed evaluation.
/// Planner eligibility and application setup share this single definition so
/// an unsupported expression never enters the synchronous dry-run path.
pub fn expression_is_effectful(expression : @syntax.Expression) -> Bool {
  match expression {
    String(_) | Boolean(_) | Variable(_) => false
    Backtick(_) | Call(_) => true
    List(elements~, ..) => elements.any(expression_is_effectful)
    Parenthesized(expression~, ..) => expression_is_effectful(expression)
    Unary(operand~, ..) => expression_is_effectful(operand)
    Binary(lhs~, rhs~, ..) =>
      expression_is_effectful(lhs) || expression_is_effectful(rhs)
    Conditional(condition~, then_branch~, else_branch~, ..) =>
      expression_is_effectful(condition) ||
      expression_is_effectful(then_branch) ||
      else_branch.map(expression_is_effectful).unwrap_or(false)
    Format(parts~, ..) =>
      parts.any(fn(part) { expression_is_effectful(part.expression()) })
  }
}
