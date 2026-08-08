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
fn short_usage(spec : RecipeSpec) -> String {
  let values : Array[String] = ["just", spec.name]
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
    if parameter.is_required() {
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
        Some(expression) =>
          @evaluator.evaluate(expression, environment=scope) catch {
            error => raise Evaluation(error)
          }
        None => bound_value(parameter, groups[index])
      }
    } else {
      bound_value(parameter, groups[index])
    }
    scope.set(parameter.name, binding)
  }
  validate_patterns(spec)
}

///|
fn parse_one(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  input : ArrayView[String],
  start : Int,
) -> (Invocation, Int) raise InvocationError {
  let (recipe, consumed) = match input.get(start) {
    Some(requested) =>
      match resolve_recipe_name(compilation, requested) {
        Some(name) => (compilation.recipe(name).unwrap(), 1)
        None => raise UnknownRecipe(recipe=requested)
      }
    None =>
      match default_recipe(compilation) {
        Some(recipe) => (recipe, 0)
        None => raise NoRecipes
      }
  }
  let spec = recipe_spec(compilation, recipe)
  let groups : Array[Array[String]] = spec.parameters.map(fn(_) { [] })
  let positional : Array[Int] = []
  let mut has_options = false
  for index, parameter in spec.parameters {
    if parameter.is_option() {
      has_options = true
    } else {
      positional.push(index)
    }
  }
  let rest = input[start + consumed:]
  let mut cursor = 0
  let mut positional_index = 0
  let mut positional_accepted = 0
  let mut end_of_options = !has_options
  while cursor < rest.length() {
    let argument = rest[cursor]
    if !end_of_options && argument == "--" {
      end_of_options = true
      cursor += 1
      continue
    }
    if !end_of_options && argument.has_prefix("-") && argument != "-" {
      let long = argument.has_prefix("--")
      let stripped = argument
        .view(start_offset=if long { 2 } else { 1 })
        .to_owned()
      let (name, supplied) = split_option(stripped)
      if name.is_empty() {
        raise InvalidOption(argument~)
      }
      if long {
        guard find_long(spec.parameters, name) is Some(index) else {
          raise UnknownOption(recipe=spec.name, option="--" + name)
        }
        let cursor_ref = Ref(cursor)
        apply_option(
          spec,
          groups,
          index,
          "--" + name,
          supplied,
          true,
          rest,
          cursor_ref,
        )
        cursor = cursor_ref.val
      } else {
        let switches = name.to_array()
        for switch_index, switch in switches {
          let option = "-" + switch.to_string()
          guard find_short(spec.parameters, switch) is Some(index) else {
            raise UnknownOption(recipe=spec.name, option~)
          }
          let cursor_ref = Ref(cursor)
          apply_option(
            spec,
            groups,
            index,
            option,
            if switch_index + 1 == switches.length() {
              supplied
            } else {
              None
            },
            switch_index + 1 == switches.length(),
            rest,
            cursor_ref,
          )
          cursor = cursor_ref.val
        }
      }
      cursor += 1
      continue
    }
    guard positional.get(positional_index) is Some(parameter_index) else {
      break
    }
    groups[parameter_index].push(argument)
    if !spec.parameters[parameter_index].variadic {
      positional_index += 1
    }
    positional_accepted += 1
    cursor += 1
  }
  let (minimum, maximum) = positional_bounds(spec)
  if consumed == 0 {
    let mut required = 0
    for parameter in spec.parameters {
      if parameter.is_required() {
        required += 1
      }
    }
    if required > 0 {
      raise DefaultRecipeRequiresArguments(recipe=spec.name, minimum=required)
    }
  }
  for index, parameter in spec.parameters {
    if groups[index].is_empty() && parameter.is_required() {
      match (parameter.long, parameter.short) {
        (Some(long), _) =>
          raise MissingOption(recipe=spec.name, option="--" + long)
        (_, Some(short)) =>
          raise MissingOption(recipe=spec.name, option="-" + short.to_string())
        _ => ()
      }
    }
  }
  if positional_accepted < minimum {
    raise PositionalArgumentCountMismatch(
      recipe=spec.name,
      found=positional_accepted,
      minimum~,
      maximum~,
      usage=short_usage(spec),
    )
  }
  resolve_values_and_patterns(recipe, spec, groups, global)
  for index, parameter in spec.parameters {
    let group = groups[index]
    match parameter.minimum {
      Some(minimum) if !group.is_empty() && group.length() < minimum =>
        raise ArgumentTooFewValues(
          recipe=spec.name,
          parameter=parameter.name,
          found=group.length(),
          minimum~,
        )
      _ => ()
    }
    match parameter.maximum {
      Some(maximum) if !group.is_empty() && group.length() > maximum =>
        raise ArgumentTooManyValues(
          recipe=spec.name,
          parameter=parameter.name,
          found=group.length(),
          maximum~,
        )
      _ => ()
    }
    for argument in group {
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
  (
    { recipe: spec.name, arguments: groups.map(fn(elements) { { elements, } }) },
    consumed + cursor,
  )
}

///|
/// Parse all recipe invocations from command-line positional arguments.
pub fn parse_invocations(
  compilation : @semantic.Compilation,
  arguments : ArrayView[String],
) -> Array[Invocation] raise InvocationError {
  let global = @evaluator.evaluate_compilation(compilation) catch {
    error => raise Evaluation(error)
  }
  if arguments.is_empty() {
    let (invocation, _) = parse_one(compilation, global, arguments, 0)
    return [invocation]
  }
  let result : Array[Invocation] = []
  let mut cursor = 0
  while cursor < arguments.length() {
    let (invocation, consumed) = parse_one(
      compilation, global, arguments, cursor,
    )
    result.push(invocation)
    cursor += consumed
  }
  result
}
