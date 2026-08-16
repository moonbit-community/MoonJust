///|
fn collect_expression_references(
  compilation : @semantic.Compilation,
  expression : @syntax.Expression,
  locals : Set[String],
  references : Set[String],
  functions : Set[String],
) -> Unit {
  match expression {
    Variable(name~, ..) =>
      if !locals.contains(name) && compilation.variable(name) is Some(_) {
        references.add(name)
      }
    Call(name~, arguments~, ..) => {
      for argument in arguments {
        collect_expression_references(
          compilation, argument, locals, references, functions,
        )
      }
      guard !functions.contains(name) else { return }
      guard compilation.function(name) is Some(definition) else { return }
      functions.add(name)
      let parameters : Set[String] = Set([])
      for parameter in definition.parameters() {
        parameters.add(parameter.name())
      }
      collect_expression_references(
        compilation,
        definition.body(),
        parameters,
        references,
        functions,
      )
    }
    List(elements~, ..) =>
      for element in elements {
        collect_expression_references(
          compilation, element, locals, references, functions,
        )
      }
    Parenthesized(expression~, ..) =>
      collect_expression_references(
        compilation, expression, locals, references, functions,
      )
    Unary(operand~, ..) =>
      collect_expression_references(
        compilation, operand, locals, references, functions,
      )
    Binary(lhs~, rhs~, ..) => {
      collect_expression_references(
        compilation, lhs, locals, references, functions,
      )
      collect_expression_references(
        compilation, rhs, locals, references, functions,
      )
    }
    Conditional(condition~, then_branch~, else_branch~, ..) => {
      collect_expression_references(
        compilation, condition, locals, references, functions,
      )
      collect_expression_references(
        compilation, then_branch, locals, references, functions,
      )
      match else_branch {
        Some(expression) =>
          collect_expression_references(
            compilation, expression, locals, references, functions,
          )
        None => ()
      }
    }
    Format(parts~, ..) =>
      for part in parts {
        collect_expression_references(
          compilation,
          part.expression(),
          locals,
          references,
          functions,
        )
      }
    String(_) | Backtick(_) | Boolean(_) => ()
  }
}

///|
fn resolved_recipe_name(
  compilation : @semantic.Compilation,
  name : String,
) -> String? {
  let seen : Set[String] = Set([])
  let mut current = name
  while compilation.alias_target(current) is Some(next) {
    if seen.contains(current) {
      return None
    }
    seen.add(current)
    current = next
  }
  if compilation.recipe(current) is Some(_) {
    Some(current)
  } else {
    None
  }
}

///|
/// Return assignment names referenced by the selected recipes, their complete
/// dependency graph, active attributes, parameter defaults, and user function
/// bodies. Names retain compilation order for deterministic effect ordering.
pub fn recipe_variable_references(
  compilation : @semantic.Compilation,
  recipe_names : ArrayView[String],
) -> Array[String] {
  let references : Set[String] = Set([])
  let functions : Set[String] = Set([])
  let visited : Set[String] = Set([])
  let stack : Array[String] = recipe_names.to_owned()
  while stack.pop() is Some(requested) {
    guard resolved_recipe_name(compilation, requested) is Some(name) else {
      continue
    }
    if visited.contains(name) {
      continue
    }
    visited.add(name)
    let recipe = compilation.recipe(name).unwrap()
    let locals : Set[String] = Set([])
    for parameter in recipe.parameters() {
      locals.add(parameter.name())
    }
    for parameter in recipe.parameters() {
      match parameter.default_value() {
        Some(expression) =>
          collect_expression_references(
            compilation, expression, locals, references, functions,
          )
        None => ()
      }
    }
    for dependency in recipe.dependencies() {
      for argument in dependency.arguments() {
        collect_expression_references(
          compilation, argument, locals, references, functions,
        )
      }
      stack.push(dependency.name())
    }
    for dependency in recipe.subsequent_dependencies() {
      for argument in dependency.arguments() {
        collect_expression_references(
          compilation, argument, locals, references, functions,
        )
      }
      stack.push(dependency.name())
    }
    for line in recipe.lines() {
      for fragment in line.fragments() {
        if fragment is Interpolation(expression~, ..) {
          collect_expression_references(
            compilation, expression, locals, references, functions,
          )
        }
      }
    }
    for attribute in recipe.attributes() {
      for argument in attribute.arguments() {
        match argument.value() {
          Some(expression) =>
            collect_expression_references(
              compilation, expression, locals, references, functions,
            )
          None => ()
        }
      }
    }
  }
  for setting_name in compilation.settings().names() {
    match compilation.settings().get(setting_name) {
      Some(Expression(expression)) =>
        collect_expression_references(
          compilation,
          expression,
          Set([]),
          references,
          functions,
        )
      _ => ()
    }
  }
  let ordered : Array[String] = []
  for name in compilation.variable_names() {
    if references.contains(name) {
      ordered.push(name)
    }
  }
  ordered
}
