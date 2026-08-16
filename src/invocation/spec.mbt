///|
fn attribute_error(
  recipe : String,
  detail : String,
  span? : @source.Span,
) -> InvocationError {
  InvalidArgumentAttribute(recipe~, detail~, span~)
}

///|
fn string_literal(
  expression : @syntax.Expression?,
  recipe : String,
  property : String,
  span? : @source.Span,
) -> String raise InvocationError {
  match expression {
    Some(String(value)) => value.cooked()
    None if property == "min" || property == "max" =>
      raise attribute_error(
        recipe,
        "attribute key `" + property + "` requires value",
        span?,
      )
    Some(_) if property == "min" || property == "max" =>
      raise attribute_error(
        recipe,
        "attribute `arg` arguments must be string literals",
        span?,
      )
    _ =>
      raise attribute_error(
        recipe,
        "`" + property + "` requires a string literal",
        span?,
      )
  }
}

///|
fn count_literal(
  expression : @syntax.Expression?,
  recipe : String,
  property : String,
  span? : @source.Span,
) -> Int raise InvocationError {
  let value = string_literal(expression, recipe, property, span?)
  let value_span = match expression {
    Some(value) => Some(value.span())
    None => span
  }
  guard !value.is_empty() && value.all(Char::is_ascii_digit) else {
    raise attribute_error(
      recipe,
      "invalid `" + property + "` value `" + value + "`",
      span?=value_span,
    )
  }
  @string.parse_int(value[:]) catch {
    _ =>
      raise attribute_error(
        recipe,
        "invalid `" +
        property +
        "` value `" +
        value +
        "`: number is out of range",
        span?=value_span,
      )
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
  span? : @source.Span,
) -> Unit raise InvocationError {
  if value.is_empty() {
    raise attribute_error(
      recipe,
      "option name for parameter `" + parameter + "` is empty",
      span?,
    )
  }
  if value.contains("=") {
    raise attribute_error(
      recipe,
      "option name for parameter `" + parameter + "` contains equal sign",
      span?,
    )
  }
  if value.has_prefix("-") {
    raise attribute_error(
      recipe,
      "option name for parameter `" + parameter + "` starts with dash",
      span?,
    )
  }
  if short && value.to_array().length() != 1 {
    raise attribute_error(
      recipe,
      "short option name for parameter `" +
      parameter +
      "` contains multiple characters",
      span?,
    )
  }
}

///|
fn compile_argument_attribute(
  spec : RecipeSpec,
  attribute : @syntax.Attribute,
  seen : Set[String],
) -> Unit raise InvocationError {
  let arguments = attribute.arguments()
  guard arguments.get(0) is Some(first) else {
    raise attribute_error(spec.name, "missing parameter name")
  }
  let name = string_literal(first.value(), spec.name, "arg", span=first.span())
  guard find_parameter(spec.parameters, name) is Some(index) else {
    raise attribute_error(
      spec.name,
      "undefined argument `" + name + "`",
      span=first.span(),
    )
  }
  if seen.contains(name) {
    raise attribute_error(
      spec.name,
      "duplicate attributes for argument `" + name + "`",
      span=attribute.span(),
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
        span=argument.span(),
      )
    }
    if keys.contains(key) {
      raise attribute_error(
        spec.name,
        "duplicate `" + key + "` property for argument `" + name + "`",
        span=argument.span(),
      )
    }
    keys.add(key)
    match key {
      "long" => {
        let value = match argument.value() {
          Some(_) =>
            string_literal(
              argument.value(),
              spec.name,
              "long",
              span=argument.span(),
            )
          None => name
        }
        let value_span = argument
          .value()
          .map(fn(expression) { expression.span() })
          .unwrap_or(argument.span())
        validate_option_name(spec.name, name, value, false, span=value_span)
        parameter.long = Some(value)
        parameter.long_span = Some(value_span)
        parameter.long_defaulted = argument.value() is None
      }
      "short" => {
        let value = match argument.value() {
          Some(_) =>
            string_literal(
              argument.value(),
              spec.name,
              "short",
              span=argument.span(),
            )
          None => name.to_array()[0].to_string()
        }
        let value_span = argument
          .value()
          .map(fn(expression) { expression.span() })
          .unwrap_or(argument.span())
        validate_option_name(spec.name, name, value, true, span=value_span)
        parameter.short = Some(value.to_array()[0])
        parameter.short_span = Some(value_span)
      }
      "flag" => {
        if argument.value() is Some(_) {
          raise attribute_error(
            spec.name,
            "`flag` attribute for argument `" + name + "` takes no value",
            span=argument.span(),
          )
        }
        parameter.flag = true
        parameter.flag_span = Some(argument.span())
      }
      "value" => {
        guard argument.value() is Some(expression) else {
          raise attribute_error(
            spec.name,
            "attribute key `value` requires value",
            span=argument.span(),
          )
        }
        parameter.value = Some(expression)
        parameter.value_span = Some(argument.span())
      }
      "multiple" => {
        if argument.value() is Some(_) {
          raise attribute_error(
            spec.name,
            "attribute key `multiple` takes no value",
            span=argument.span(),
          )
        }
        parameter.multiple = true
        parameter.multiple_span = Some(argument.span())
      }
      "min" => {
        parameter.minimum = Some(
          count_literal(
            argument.value(),
            spec.name,
            "min",
            span=argument.span(),
          ),
        )
        parameter.minimum_span = Some(argument.span())
      }
      "max" => {
        parameter.maximum = Some(
          count_literal(
            argument.value(),
            spec.name,
            "max",
            span=argument.span(),
          ),
        )
        parameter.maximum_span = Some(argument.span())
      }
      "pattern" => {
        guard argument.value() is Some(expression) else {
          raise attribute_error(
            spec.name,
            "attribute key `pattern` requires value",
            span=argument.span(),
          )
        }
        parameter.pattern = Some(expression)
        parameter.pattern_span = Some(argument.span())
        match expression {
          String(value) => parameter.patterns = [value.cooked()]
          List(elements~, ..) => {
            let patterns : Array[String] = []
            for element in elements {
              if element is String(value) {
                patterns.push(value.cooked())
              }
            }
            parameter.patterns = patterns
          }
          _ => ()
        }
      }
      "help" =>
        ignore(
          string_literal(
            argument.value(),
            spec.name,
            "help",
            span=argument.span(),
          ),
        )
      _ =>
        raise attribute_error(
          spec.name,
          "unknown property `" + key + "`",
          span=argument.span(),
        )
    }
  }
  if !parameter.is_option() &&
    (parameter.flag || parameter.value is Some(_) || parameter.multiple) {
    let mode_span = match
      (parameter.flag_span, parameter.value_span, parameter.multiple_span) {
      (Some(span), _, _) | (_, Some(span), _) | (_, _, Some(span)) => Some(span)
      _ => None
    }
    let mode = if parameter.flag {
      "flag"
    } else if parameter.value is Some(_) {
      "value"
    } else {
      "multiple"
    }
    raise attribute_error(
      spec.name,
      "argument attribute `" + mode + "` only valid with `long` or `short`",
      span?=mode_span,
    )
  }
  if parameter.flag && parameter.value is Some(_) {
    raise attribute_error(
      spec.name,
      "argument `" + name + "` may not have both `flag` and `value` attributes",
      span?=parameter.flag_span,
    )
  }
  if parameter.flag && parameter.pattern is Some(_) {
    raise attribute_error(
      spec.name,
      "argument `" +
      name +
      "` may not have both `flag` and `pattern` attributes",
      span?=parameter.flag_span,
    )
  }
  if parameter.flag && parameter.defaulted {
    raise attribute_error(
      spec.name,
      "flag parameter `" + name + "` may not have a default",
      span=parameter.span,
    )
  }
  if (parameter.minimum is Some(_) || parameter.maximum is Some(_)) &&
    !parameter.multiple &&
    !parameter.variadic {
    let bounds_span = match (parameter.minimum_span, parameter.maximum_span) {
      (Some(span), _) | (_, Some(span)) => Some(span)
      _ => None
    }
    let bound = if parameter.minimum is Some(_) { "min" } else { "max" }
    raise attribute_error(
      spec.name,
      "argument attribute `" +
      bound +
      "` only valid with `multiple` or a variadic parameter",
      span?=bounds_span,
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
        span?=parameter.minimum_span,
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
          raise DuplicateDefinitionOption(
            recipe=spec.name,
            option="--" + a,
            span=if right.long_defaulted {
              left.long_span.unwrap_or(left.span)
            } else {
              right.long_span.unwrap_or(right.span)
            },
          )
        _ => ()
      }
      match (left.short, right.short) {
        (Some(a), Some(b)) if a == b =>
          raise DuplicateDefinitionOption(
            recipe=spec.name,
            option="-" + a.to_string(),
            span=right.short_span.unwrap_or(right.span),
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
              span?=parameter.pattern_span,
            )
        },
      )
      ignore(
        @regexp.compile(("^(?:" + pattern + ")$")[:]) catch {
          _ =>
            raise attribute_error(
              spec.name,
              "invalid pattern `" + pattern + "`",
              span?=parameter.pattern_span,
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
        span: parameter.span(),
        defaulted: parameter.default_value() is Some(_),
        variadic: parameter.variadic(),
        variadic_minimum: parameter.variadic_minimum(),
        long: None,
        short: None,
        long_defaulted: false,
        flag: false,
        value: None,
        multiple: false,
        minimum: None,
        maximum: None,
        pattern: None,
        patterns: [],
        long_span: None,
        short_span: None,
        flag_span: None,
        value_span: None,
        multiple_span: None,
        minimum_span: None,
        maximum_span: None,
        pattern_span: None,
      }
    }),
  }
  let seen : Set[String] = Set([])
  for attribute in recipe.attributes() {
    if attribute.name() == "arg" {
      compile_argument_attribute(spec, attribute, seen)
    }
  }
  validate_unique_options(spec)
  validate_patterns(spec)
  if !compilation.settings().bool("lists") {
    for parameter in spec.parameters {
      if parameter.flag {
        raise attribute_error(
          spec.name,
          "`flag` arguments require `set lists`",
          span?=parameter.flag_span,
        )
      }
      if parameter.multiple {
        raise attribute_error(
          spec.name,
          "`[arg(multiple)]` requires `set lists`",
          span?=parameter.multiple_span,
        )
      }
      if parameter.minimum is Some(_) {
        raise attribute_error(
          spec.name,
          "`[arg(min)]` requires `set lists`",
          span?=parameter.minimum_span,
        )
      }
      if parameter.maximum is Some(_) {
        raise attribute_error(
          spec.name,
          "`[arg(max)]` requires `set lists`",
          span?=parameter.maximum_span,
        )
      }
    }
  }
  spec
}

///|
/// Return the expression used to materialize a value-less option occurrence.
/// The invocation parser owns argument-attribute validation, so callers receive
/// the same diagnostics as normal command-line parsing.
pub fn recipe_argument_value_expression(
  compilation : @semantic.Compilation,
  recipe_name : String,
  parameter_name : String,
) -> @syntax.Expression? raise InvocationError {
  guard compilation.recipe(recipe_name) is Some(recipe) else {
    raise UnknownRecipe(recipe=recipe_name)
  }
  let spec = recipe_spec(compilation, recipe)
  match find_parameter(spec.parameters, parameter_name) {
    Some(index) => spec.parameters[index].value
    None => None
  }
}
