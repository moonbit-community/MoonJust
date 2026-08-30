///|
fn resolve_recipe_name(
  compilation : @semantic.Compilation,
  requested : String,
) -> String? {
  let seen : Set[String] = Set([])
  let mut current = requested
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
fn default_recipe(compilation : @semantic.Compilation) -> @syntax.Recipe? {
  for name in compilation.recipe_names() {
    match compilation.recipe_attributes(name) {
      Some(attributes) if attributes.names().contains("default") =>
        return compilation.recipe(name)
      _ => ()
    }
  }
  match compilation.recipe_names().get(0) {
    Some(name) => compilation.recipe(name)
    None => None
  }
}

///|
fn short_usage(spec : RecipeSpec, display_name? : String) -> String {
  let values : Array[String] = ["just", display_name.unwrap_or(spec.name)]
  if spec.parameters.any(ParameterSpec::is_option) {
    values.push("[OPTIONS]")
  }
  for parameter in spec.parameters {
    if parameter.is_option() {
      continue
    }
    let label = parameter.name + (if parameter.variadic { "..." } else { "" })
    values.push(if parameter.is_required() { label } else { "[" + label + "]" })
  }
  values.join(" ")
}

///|
fn positional_bounds(spec : RecipeSpec) -> (Int, Int?) {
  let mut minimum = 0
  let mut maximum = 0
  let mut unbounded = false
  for parameter in spec.parameters {
    if parameter.is_option() {
      continue
    }
    if parameter.is_required() && parameter.minimum is None {
      minimum += 1
    }
    if parameter.variadic {
      unbounded = true
    } else {
      maximum += 1
    }
  }
  (minimum, if unbounded { None } else { Some(maximum) })
}

///|
fn split_option(argument : String) -> (String, String?) {
  match argument.find("=") {
    Some(index) =>
      (argument[:index].to_owned(), Some(argument[index + 1:].to_owned()))
    None => (argument, None)
  }
}

///|
fn find_long(parameters : Array[ParameterSpec], name : String) -> Int? {
  for index, parameter in parameters {
    if parameter.long == Some(name) {
      return Some(index)
    }
  }
  None
}

///|
fn find_short(parameters : Array[ParameterSpec], name : Char) -> Int? {
  for index, parameter in parameters {
    if parameter.short == Some(name) {
      return Some(index)
    }
  }
  None
}

///|
fn apply_option(
  spec : RecipeSpec,
  groups : Array[Array[String]],
  parameter_index : Int,
  option : String,
  supplied : String?,
  is_final : Bool,
  rest : ArrayView[String],
  cursor : Ref[Int],
) -> Unit raise InvocationError {
  let parameter = spec.parameters[parameter_index]
  let value = if parameter.flag || parameter.value is Some(_) {
    if supplied is Some(_) {
      raise FlagWithValue(recipe=spec.name, option~)
    }
    "true"
  } else if !is_final {
    raise NonFinalOptionWithValue(recipe=spec.name, option~)
  } else {
    match supplied {
      Some(value) => value
      None =>
        match rest.get(cursor.val + 1) {
          Some(value) => {
            cursor.val += 1
            value
          }
          None => raise OptionMissingValue(recipe=spec.name, option~)
        }
    }
  }
  if !groups[parameter_index].is_empty() &&
    !parameter.variadic &&
    !parameter.multiple {
    raise DuplicateOption(recipe=spec.name, option~)
  }
  groups[parameter_index].push(value)
}

///|
fn matches_any(patterns : ArrayView[String], value : String) -> Bool {
  for pattern in patterns {
    let regexp = @regexp.compile(("^(?:" + pattern + ")$")[:]) catch {
      _ => return false
    }
    if regexp.execute(value[:]).matched() {
      return true
    }
  }
  false
}

///|
fn value_elements(value : @value.Value) -> Array[String] {
  match value {
    String(text) => [text]
    List(values) => values.map(@value.Value::to_string)
    Bool(value) => [value.to_string()]
  }
}

///|
pub fn validate_recipe_argument_values(
  compilation : @semantic.Compilation,
  recipe_name : String,
  arguments : ArrayView[@value.Value],
  global : @evaluator.Environment,
) -> Unit raise InvocationError {
  guard compilation.recipe(recipe_name) is Some(recipe) else {
    raise UnknownRecipe(recipe=recipe_name)
  }
  let spec = recipe_spec(compilation, recipe)
  for parameter in spec.parameters {
    match parameter.pattern {
      Some(expression) => {
        let value = @evaluator.evaluate(expression, environment=global) catch {
          error => raise Evaluation(error)
        }
        parameter.patterns = value_elements(value)
      }
      None => ()
    }
  }
  validate_patterns(spec)
  let mut cursor = 0
  for parameter in spec.parameters {
    let elements : Array[String] = []
    if parameter.variadic {
      for argument in arguments[cursor:] {
        elements.append(argument.elements())
      }
      cursor = arguments.length()
    } else if arguments.get(cursor) is Some(argument) {
      elements.append(argument.elements())
      cursor += 1
    }
    match parameter.minimum {
      Some(minimum) if elements.length() < minimum =>
        raise ArgumentTooFewValues(
          recipe=spec.name,
          parameter=parameter.name,
          found=elements.length(),
          minimum~,
        )
      _ => ()
    }
    match parameter.maximum {
      Some(maximum) if elements.length() > maximum =>
        raise ArgumentTooManyValues(
          recipe=spec.name,
          parameter=parameter.name,
          found=elements.length(),
          maximum~,
        )
      _ => ()
    }
    for argument in elements {
      if !parameter.patterns.is_empty() &&
        !matches_any(parameter.patterns, argument) {
        raise ArgumentPatternMismatch(
          recipe=spec.name,
          parameter=parameter.name,
          argument~,
          patterns=parameter.patterns.copy(),
        )
      }
    }
  }
}

///|
fn bound_value(
  parameter : ParameterSpec,
  elements : ArrayView[String],
) -> @value.Value {
  if parameter.variadic ||
    parameter.multiple ||
    parameter.flag ||
    elements.length() > 1 {
    List(elements.map(fn(value) { String(value) }))
  } else {
    String(elements.get(0).unwrap_or(""))
  }
}

///|
fn resolve_values_and_patterns(
  recipe : @syntax.Recipe,
  spec : RecipeSpec,
  groups : Array[Array[String]],
  global : @evaluator.Environment,
  resolve_defaults? : Bool = true,
) -> Unit raise InvocationError {
  let scope = @evaluator.Environment::child(global)
  for index, parameter in spec.parameters {
    match parameter.pattern {
      Some(expression) => {
        let value = @evaluator.evaluate(expression, environment=global) catch {
          error => raise Evaluation(error)
        }
        parameter.patterns = value_elements(value)
      }
      None => ()
    }
    match parameter.value {
      Some(expression) if !groups[index].is_empty() => {
        let occurrences = groups[index].length()
        let resolved : Array[String] = []
        for _ in 0..<occurrences {
          let value = @evaluator.evaluate(expression, environment=scope) catch {
            error => raise Evaluation(error)
          }
          resolved.append(value_elements(value))
        }
        groups[index] = resolved
      }
      _ => ()
    }
    let binding = if groups[index].is_empty() {
      match recipe.parameters()[index].default_value() {
        Some(expression) if resolve_defaults =>
          try @evaluator.evaluate(expression, environment=scope) catch {
            EffectRequired(_) => bound_value(parameter, groups[index])
            error => raise Evaluation(error)
          } noraise {
            value => {
              groups[index] = value_elements(value)
              value
            }
          }
        _ => bound_value(parameter, groups[index])
      }
    } else {
      bound_value(parameter, groups[index])
    }
    scope.set(parameter.name, binding)
  }
  validate_patterns(spec)
}

///|
