///|
/// The synchronous dry-run planner excludes every call and backtick, including
/// pure builtins. Nested expressions inherit the same restriction.
pub fn expression_requires_async_path(expression : @syntax.Expression) -> Bool {
  match expression {
    String(_) | Boolean(_) | Variable(_) => false
    Backtick(_) | Call(_) => true
    List(elements~, ..) => elements.any(expression_requires_async_path)
    Parenthesized(expression~, ..) => expression_requires_async_path(expression)
    Unary(operand~, ..) => expression_requires_async_path(operand)
    Binary(lhs~, rhs~, ..) =>
      expression_requires_async_path(lhs) || expression_requires_async_path(rhs)
    Conditional(condition~, then_branch~, else_branch~, ..) =>
      expression_requires_async_path(condition) ||
      expression_requires_async_path(then_branch) ||
      else_branch.map(expression_requires_async_path).unwrap_or(false)
    Format(parts~, ..) =>
      parts.any(fn(part) { expression_requires_async_path(part.expression()) })
  }
}
