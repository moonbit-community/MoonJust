///|
fn parse_one(
  compilation : @semantic.Compilation,
  global : @evaluator.Environment,
  input : ArrayView[String],
  start : Int,
  resolve_expressions? : Bool = true,
  display_name? : String,
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
  let mut saw_terminator = false
  while cursor < rest.length() {
    let argument = rest[cursor]
    if !end_of_options && argument == "--" {
      end_of_options = true
      saw_terminator = true
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
      usage=short_usage(spec, display_name?),
    )
  }
  if resolve_expressions {
    resolve_values_and_patterns(
      recipe,
      spec,
      groups,
      global,
      resolve_defaults=!saw_terminator,
    )
  }
  if resolve_expressions {
    for index, parameter in spec.parameters {
      let group = groups[index]
      match parameter.minimum {
        Some(minimum) if group.length() < minimum =>
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
  }
  let arguments : Array[ArgumentValue] = []
  for index, elements in groups {
    let parameter = spec.parameters[index]
    arguments.push({
      elements,
      list: parameter.flag || parameter.multiple || parameter.variadic,
    })
  }
  ({ recipe: spec.name, arguments, }, consumed + cursor)
}

///|
/// Resolve command-line recipe targets without evaluating parameter defaults,
/// patterns, or value expressions. Execution uses this first pass to determine
/// the assignment closure required by `set lazy`.
pub fn parse_project_invocation_targets(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
  allow_missing? : Bool = false,
) -> Array[(@modulepath.ModulePath, String)] raise InvocationError {
  let result : Array[(@modulepath.ModulePath, String)] = []
  let mut cursor = 0
  while cursor < arguments.length() || result.is_empty() {
    let resolved = try
      Some(resolve_project_recipe(project, arguments, cursor))
    catch {
      UnknownRecipe(_)
      | UnknownRecipeSuggested(_)
      | UnknownSubmodule(_)
      | OptionalModuleAbsent(_) if allow_missing => None
      error => raise error
    } noraise {
      value => value
    }
    guard resolved is Some((module_path, recipe, path_consumed)) else {
      cursor += 1
      if cursor >= arguments.length() {
        break
      }
      continue
    }
    let compilation = project.module_compilation(module_path).unwrap()
    let synthetic : Array[String] = [recipe]
    for value in arguments[cursor + path_consumed:] {
      synthetic.push(value)
    }
    let (_, consumed) = parse_one(
      compilation,
      @evaluator.Environment::new(),
      synthetic,
      0,
      resolve_expressions=false,
      display_name=arguments[cursor:cursor + path_consumed].join("::"),
    )
    result.push((module_path, recipe))
    cursor += path_consumed + consumed - 1
    if cursor >= arguments.length() {
      break
    }
  }
  result
}

///|
/// Parse all recipe invocations from command-line positional arguments.
pub fn parse_invocations(
  compilation : @semantic.Compilation,
  arguments : ArrayView[String],
  overrides? : ArrayView[(String, String)] = [],
) -> Array[Invocation] raise InvocationError {
  let global = @evaluator.evaluate_compilation(compilation, overrides~) catch {
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

///|
