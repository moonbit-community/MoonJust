///|
fn attribute_error(recipe : String, detail : String) -> InvocationError {
  InvalidArgumentAttribute(recipe~, detail~)
}

///|
fn string_literal(
  expression : @syntax.Expression?,
  recipe : String,
  property : String,
) -> String raise InvocationError {
  match expression {
    Some(String(value)) => value.cooked()
    _ =>
      raise attribute_error(
        recipe,
        "`" + property + "` requires a string literal",
      )
  }
}

///|
fn count_literal(
  expression : @syntax.Expression?,
  recipe : String,
  property : String,
) -> Int raise InvocationError {
  let value = string_literal(expression, recipe, property)
  guard !value.is_empty() && value.all(Char::is_ascii_digit) else {
    raise attribute_error(
      recipe,
      "`" + property + "` must be a non-negative integer",
    )
  }
  @string.parse_int(value[:]) catch {
    _ => raise attribute_error(recipe, "`" + property + "` is out of range")
  }
}

///|
fn find_parameter(parameters : Array[ParameterSpec], name : String) -> Int? {
  for index, parameter in parameters {
    if parameter.name == name {
      return Some(index)
    }
  }
  None
}

///|
fn validate_option_name(
  recipe : String,
  parameter : String,
  value : String,
  short : Bool,
) -> Unit raise InvocationError {
  if value.is_empty() {
    raise attribute_error(
      recipe,
      "option name for parameter `" + parameter + "` is empty",
    )
  }
  if value.contains("=") {
    raise attribute_error(
      recipe,
      "option name for parameter `" + parameter + "` contains equal sign",
    )
  }
  if value.has_prefix("-") {
    raise attribute_error(
      recipe,
      "option name for parameter `" + parameter + "` starts with dash",
    )
  }
  if short && value.to_array().length() != 1 {
    raise attribute_error(
      recipe,
      "short option name for parameter `" +
      parameter +
      "` contains multiple characters",
    )
  }
}

///|
fn compile_argument_attribute(
  spec : RecipeSpec,
  arguments : ArrayView[@syntax.AttributeArgument],
  seen : Set[String],
) -> Unit raise InvocationError {
  guard arguments.get(0) is Some(first) else {
    raise attribute_error(spec.name, "missing parameter name")
  }
  let name = string_literal(first.value(), spec.name, "arg")
  guard find_parameter(spec.parameters, name) is Some(index) else {
    raise attribute_error(spec.name, "undefined argument `" + name + "`")
  }
  if seen.contains(name) {
    raise attribute_error(
      spec.name,
      "duplicate attributes for argument `" + name + "`",
    )
  }
  seen.add(name)
  let parameter = spec.parameters[index]
  let keys : Set[String] = Set([])
  for argument in arguments[1:] {
    guard argument.key() is Some(key) else {
      raise attribute_error(
        spec.name,
        "unexpected positional property for argument `" + name + "`",
      )
    }
    if keys.contains(key) {
      raise attribute_error(
        spec.name,
        "duplicate `" + key + "` property for argument `" + name + "`",
      )
    }
    keys.add(key)
    match key {
      "long" => {
        let value = match argument.value() {
          Some(_) => string_literal(argument.value(), spec.name, "long")
          None => name
        }
        validate_option_name(spec.name, name, value, false)
        parameter.long = Some(value)
      }
      "short" => {
        let value = match argument.value() {
          Some(_) => string_literal(argument.value(), spec.name, "short")
          None => name.to_array()[0].to_string()
        }
        validate_option_name(spec.name, name, value, true)
        parameter.short = Some(value.to_array()[0])
      }
      "flag" => {
        if argument.value() is Some(_) {
          raise attribute_error(spec.name, "`flag` does not take a value")
        }
        parameter.flag = true
      }
      "value" => {
        guard argument.value() is Some(expression) else {
          raise attribute_error(spec.name, "`value` requires an expression")
        }
        parameter.value = Some(expression)
      }
      "multiple" => {
        if argument.value() is Some(_) {
          raise attribute_error(spec.name, "`multiple` does not take a value")
        }
        parameter.multiple = true
      }
      "min" =>
        parameter.minimum = Some(
          count_literal(argument.value(), spec.name, "min"),
        )
      "max" =>
        parameter.maximum = Some(
          count_literal(argument.value(), spec.name, "max"),
        )
      "pattern" => {
        guard argument.value() is Some(expression) else {
          raise attribute_error(spec.name, "`pattern` requires an expression")
        }
        parameter.pattern = Some(expression)
      }
      "help" => ignore(string_literal(argument.value(), spec.name, "help"))
      _ => raise attribute_error(spec.name, "unknown property `" + key + "`")
    }
  }
  if !parameter.is_option() &&
    (parameter.flag || parameter.value is Some(_) || parameter.multiple) {
    raise attribute_error(
      spec.name,
      "`flag`, `value`, and `multiple` require `long` or `short`",
    )
  }
  if parameter.flag && parameter.value is Some(_) {
    raise attribute_error(
      spec.name,
      "argument `" + name + "` may not have both `flag` and `value`",
    )
  }
  if parameter.flag && !parameter.patterns.is_empty() {
    raise attribute_error(
      spec.name,
      "argument `" + name + "` may not have both `flag` and `pattern`",
    )
  }
  if parameter.flag && parameter.defaulted {
    raise attribute_error(
      spec.name,
      "flag argument `" + name + "` may not have a default",
    )
  }
  if (parameter.minimum is Some(_) || parameter.maximum is Some(_)) &&
    !parameter.multiple &&
    !parameter.variadic {
    raise attribute_error(
      spec.name,
      "`min` and `max` require `multiple` or a variadic parameter",
    )
  }
  match (parameter.minimum, parameter.maximum) {
    (Some(minimum), Some(maximum)) if minimum > maximum =>
      raise attribute_error(
        spec.name,
        "`min` `" +
        minimum.to_string() +
        "` exceeds `max` `" +
        maximum.to_string() +
        "`",
      )
    _ => ()
  }
}

///|
fn validate_unique_options(spec : RecipeSpec) -> Unit raise InvocationError {
  for index, left in spec.parameters {
    for right in spec.parameters[index + 1:] {
      match (left.long, right.long) {
        (Some(a), Some(b)) if a == b =>
          raise attribute_error(
            spec.name,
            "option `--" + a + "` is defined multiple times",
          )
        _ => ()
      }
      match (left.short, right.short) {
        (Some(a), Some(b)) if a == b =>
          raise attribute_error(
            spec.name,
            "option `-" + a.to_string() + "` is defined multiple times",
          )
        _ => ()
      }
    }
  }
}

///|
fn validate_patterns(spec : RecipeSpec) -> Unit raise InvocationError {
  for parameter in spec.parameters {
    for pattern in parameter.patterns {
      ignore(
        @regexp.compile(pattern[:]) catch {
          _ =>
            raise attribute_error(
              spec.name,
              "invalid pattern `" + pattern + "`",
            )
        },
      )
      ignore(
        @regexp.compile(("^(?:" + pattern + ")$")[:]) catch {
          _ =>
            raise attribute_error(
              spec.name,
              "invalid pattern `" + pattern + "`",
            )
        },
      )
    }
  }
}

///|
fn recipe_spec(
  compilation : @semantic.Compilation,
  recipe : @syntax.Recipe,
) -> RecipeSpec raise InvocationError {
  let spec : RecipeSpec = {
    name: recipe.name(),
    parameters: recipe
    .parameters()
    .map(fn(parameter) {
      {
        name: parameter.name(),
        defaulted: parameter.default_value() is Some(_),
        variadic: parameter.variadic(),
        variadic_minimum: parameter.variadic_minimum(),
        long: None,
        short: None,
        flag: false,
        value: None,
        multiple: false,
        minimum: None,
        maximum: None,
        pattern: None,
        patterns: [],
      }
    }),
  }
  let seen : Set[String] = Set([])
  for attribute in recipe.attributes() {
    if attribute.name() == "arg" {
      compile_argument_attribute(spec, attribute.arguments(), seen)
    }
  }
  validate_unique_options(spec)
  if !compilation.settings().bool("lists") {
    for parameter in spec.parameters {
      if parameter.flag {
        raise attribute_error(spec.name, "`flag` arguments require `set lists`")
      }
      if parameter.multiple {
        raise attribute_error(
          spec.name,
          "`[arg(multiple)]` requires `set lists`",
        )
      }
    }
  }
  spec
}
