///|
fn recipe_line_is_comment(line : @syntax.RecipeLine) -> Bool {
  match line.fragments().get(0) {
    Some(Text(text~, ..)) => text.has_prefix("#")
    _ => false
  }
}

///|
fn recipe_line_is_continuation(line : @syntax.RecipeLine) -> Bool {
  match line.fragments().last() {
    Some(Text(text~, ..)) => text.has_suffix("\\")
    _ => false
  }
}

///|
fn semantic_recipe_has_shebang(recipe : @syntax.Recipe) -> Bool {
  guard recipe.lines().get(0) is Some(line) else { return false }
  guard line.fragments().get(0) is Some(Text(text~, ..)) else { return false }
  text.has_prefix("#!")
}

///|
fn validate_recipe_expressions(
  recipe : @syntax.Recipe,
  variables : Set[String],
  const_variables : Set[String],
  functions : Map[String, @syntax.FunctionDefinition],
  ignore_comments : Bool,
) -> Unit raise SemanticError {
  let locals : Set[String] = Set([])
  for parameter in recipe.parameters() {
    match parameter.default_value() {
      Some(value) =>
        validate_expression_semantics(value, variables, locals, functions)
      None => ()
    }
    locals.add(parameter.name())
  }
  for dependency in recipe.dependencies() {
    for argument in dependency.arguments() {
      validate_expression_semantics(argument, variables, locals, functions)
    }
  }
  for dependency in recipe.subsequent_dependencies() {
    for argument in dependency.arguments() {
      validate_expression_semantics(argument, variables, locals, functions)
    }
  }
  let mut continued = false
  for line in recipe.lines() {
    if ignore_comments && !continued && recipe_line_is_comment(line) {
      continued = false
      continue
    }
    for fragment in line.fragments() {
      if fragment is Interpolation(expression~, ..) {
        validate_expression_semantics(expression, variables, locals, functions)
      }
    }
    continued = recipe_line_is_continuation(line)
  }
  for attribute in recipe.attributes() {
    for argument in attribute.arguments() {
      match argument.value() {
        Some(value) =>
          validate_expression_semantics(
            value,
            variables,
            if attribute.name() == "env" {
              Set([])
            } else {
              locals
            },
            functions,
          )
        None => ()
      }
    }
    if attribute.name() == "doc" {
      for argument in attribute.arguments() {
        match argument.value() {
          Some(value) =>
            validate_const_expression(value, variables, const_variables)
          None => ()
        }
      }
    } else if attribute.name() == "arg" {
      for argument in attribute.arguments()[1:] {
        if argument.key() is Some("help" | "pattern") {
          match argument.value() {
            Some(value) =>
              validate_const_expression(value, variables, const_variables)
            None => ()
          }
        }
      }
    }
  }
}

///|
fn validate_recipe_sigils(
  recipe : @syntax.Recipe,
  guards : Bool,
  ignore_comments : Bool,
) -> Unit raise SemanticError {
  if !guards {
    return
  }
  let mut continued = false
  for line in recipe.lines() {
    if ignore_comments && !continued && recipe_line_is_comment(line) {
      continued = false
      continue
    }
    if continued {
      continued = recipe_line_is_continuation(line)
      continue
    }
    guard line.fragments().get(0) is Some(Text(text~, span~)) else {
      continued = recipe_line_is_continuation(line)
      continue
    }
    let mut infallible = false
    let mut is_guard = false
    let mut offset = 0
    while offset < text.length() {
      match text.unsafe_get(offset) {
        '-' => {
          if infallible {
            break
          }
          infallible = true
        }
        '?' => {
          if is_guard {
            break
          }
          is_guard = true
        }
        '@' => ()
        _ => break
      }
      offset += 1
    }
    if infallible && is_guard {
      raise GuardAndInfallibleSigil(span~)
    }
    continued = recipe_line_is_continuation(line)
  }
}

///|
fn validate_shell_recipe_indentation(
  recipe : @syntax.Recipe,
) -> Unit raise SemanticError {
  let mut continued = false
  for line in recipe.lines() {
    if !continued {
      match line.fragments().get(0) {
        Some(Text(text~, span~)) if text.has_prefix(" ") ||
          text.has_prefix("\t") =>
          raise InvalidIndentation(
            message="recipe line has extra leading whitespace",
            span~,
          )
        _ => ()
      }
    }
    continued = recipe_line_is_continuation(line)
  }
}

///|
/// Compile the complete language after the portable empty-recipe path has
/// rejected the input.
