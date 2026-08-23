///|
/// Bind recipe parameters in a child scope. Defaults may reference parent
/// values and parameters bound earlier in declaration order.
pub fn bind_recipe_parameters(
  recipe : @syntax.Recipe,
  arguments : Array[@value.Value],
  parent : Environment,
  limits? : EvaluationLimits = EvaluationLimits::default(),
  allow_empty? : Set[String] = Set([]),
  lists? : Bool = false,
) -> Environment raise EvaluationError {
  let parameters = recipe.parameters()
  let mut minimum = 0
  let mut has_variadic = false
  for parameter in parameters {
    if parameter.variadic() {
      has_variadic = true
    }
    if allow_empty.contains(parameter.name()) {
      continue
    } else if parameter.variadic() {
      minimum += parameter.variadic_minimum()
    } else if parameter.default_value() is None {
      minimum += 1
    }
  }
  let maximum : Int? = if has_variadic {
    None
  } else {
    Some(parameters.length())
  }
  if arguments.length() < minimum ||
    (match maximum {
      Some(value) => arguments.length() > value
      None => false
    }) {
    let expected = match maximum {
      Some(value) =>
        if value == minimum {
          value.to_string()
        } else {
          minimum.to_string() + " to " + value.to_string()
        }
      None => "at least " + minimum.to_string()
    }
    raise ArgumentCount(
      recipe=recipe.name(),
      expected~,
      actual=arguments.length(),
      span=recipe.span(),
    )
  }
  let scope = Environment::child(parent)
  let mut argument_index = 0
  for parameter in parameters {
    let value : @value.Value = if parameter.variadic() {
      let rest : Array[@value.Value] = []
      for argument in arguments[argument_index:] {
        rest.push(argument)
      }
      argument_index = arguments.length()
      let value : @value.Value = if rest.is_empty() && !lists {
        String("")
      } else {
        List(rest)
      }
      if parameter.variadic_minimum() > 0 && value.elements().is_empty() {
        raise EmptyParameter(
          recipe=recipe.name(),
          parameter=parameter.name(),
          span=parameter.span(),
        )
      }
      value
    } else if argument_index < arguments.length() {
      let value = arguments[argument_index]
      argument_index += 1
      if value.elements().is_empty() && !allow_empty.contains(parameter.name()) {
        match parameter.default_value() {
          Some(expression) => evaluate(expression, environment=scope, limits~)
          None =>
            raise EmptyParameter(
              recipe=recipe.name(),
              parameter=parameter.name(),
              span=parameter.span(),
            )
        }
      } else {
        value
      }
    } else {
      match parameter.default_value() {
        Some(expression) => evaluate(expression, environment=scope, limits~)
        None if allow_empty.contains(parameter.name()) => List([])
        None =>
          raise ArgumentCount(
            recipe=recipe.name(),
            expected="at least " + minimum.to_string(),
            actual=arguments.length(),
            span=parameter.span(),
          )
      }
    }
    scope.set(parameter.name(), value)
    if parameter.exported() {
      scope.mark_exported(parameter.name())
    }
  }
  scope
}
