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
fn project_overrides(
  path : @modulepath.ModulePath,
  overrides : ArrayView[(String, String)],
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  let prefix = if path.is_root() { "" } else { path.as_string() + "::" }
  for entry in overrides {
    let (name, value) = entry
    if path.is_root() {
      if !name.contains("::") {
        result.push((name, value))
      }
    } else if name.has_prefix(prefix) {
      result.push((name.view(start_offset=prefix.length()).to_owned(), value))
    }
  }
  result
}

///|
fn require_project_default_recipe(
  project : @semantic.ProjectCompilation,
  path : @modulepath.ModulePath,
) -> @syntax.Recipe raise InvocationError {
  let compilation = project.module_compilation(path).unwrap()
  guard project.default_recipe(path) is Some(name) else {
    if compilation.recipe_names().is_empty() {
      raise NoRecipes
    }
    raise NoDefaultRecipe
  }
  let recipe = compilation.recipe(name).unwrap()
  let spec = recipe_spec(compilation, recipe)
  let mut required = 0
  for parameter in spec.parameters {
    if parameter.is_required() {
      required += 1
    }
  }
  if required > 0 {
    raise DefaultRecipeRequiresArguments(recipe=spec.name, minimum=required)
  }
  recipe
}

///|
fn module_names(paths : ArrayView[@modulepath.ModulePath]) -> Array[String] {
  let result = paths.map(fn(path) { path.as_string() })
  result.sort()
  result
}

///|
fn ensure_project_recipe_available(
  project : @semantic.ProjectCompilation,
  address : @semantic.ProjectRecipe,
  requested : String,
) -> Unit raise InvocationError {
  let parsed = try @modulepath.ModulePath::parse(requested) catch {
    _ => return
  } noraise {
    value => value
  }
  let local_name = parsed.components().last().unwrap_or(requested)
  let compilation = project.module_compilation(address.module_path()).unwrap()
  if compilation.alias_target(local_name) is Some(_) &&
    project.alias_disabled(address.module_path(), local_name) {
    raise DisabledRecipe(
      name=local_name,
      modules=module_names(
        project.alias_absent_modules(address.module_path(), local_name),
      ),
      is_alias=true,
    )
  }
  if project.recipe_disabled(address.module_path(), address.recipe_name()) {
    raise DisabledRecipe(
      name=local_name,
      modules=module_names(
        project.recipe_absent_modules(
          address.module_path(),
          address.recipe_name(),
        ),
      ),
      is_alias=false,
    )
  }
}

///|
fn invocation_edit_distance(left : String, right : String) -> Int {
  let a = left.to_array()
  let b = right.to_array()
  let previous : Array[Int] = Array::make(b.length() + 1, 0)
  let current : Array[Int] = Array::make(b.length() + 1, 0)
  for index in 0..<=b.length() {
    previous[index] = index
  }
  for row in 1..<=a.length() {
    current[0] = row
    for column in 1..<=b.length() {
      let substitution = previous[column - 1] +
        (if a[row - 1] == b[column - 1] { 0 } else { 1 })
      current[column] = Int::min(
        substitution,
        Int::min(previous[column] + 1, current[column - 1] + 1),
      )
    }
    for column in 0..<=b.length() {
      previous[column] = current[column]
    }
  }
  previous[b.length()]
}

///|
fn closest_invocation_name(
  requested : String,
  names : Array[String],
) -> String? {
  names.sort()
  let mut result : String? = None
  let mut best = 3
  for name in names {
    let distance = invocation_edit_distance(requested, name)
    if distance < best {
      best = distance
      result = Some(name)
    }
  }
  result
}

///|
fn unknown_project_recipe(
  compilation : @semantic.Compilation,
  requested : String,
  local_name : String,
) -> InvocationError {
  let names : Array[String] = []
  for symbol in compilation.symbols() {
    let visible = match symbol.kind() {
      Recipe =>
        !symbol.name().has_prefix("_") &&
        compilation
        .recipe_attributes(symbol.name())
        .map(fn(attributes) { !attributes.private() })
        .unwrap_or(true)
      Alias =>
        !symbol.name().has_prefix("_") &&
        !compilation.alias_private(symbol.name())
      _ => false
    }
    if visible {
      names.push(symbol.name())
    }
  }
  match closest_invocation_name(local_name, names) {
    Some(suggestion) =>
      UnknownRecipeSuggested(
        recipe=requested,
        suggestion~,
        alias_target=compilation.alias_target(suggestion),
      )
    None => UnknownRecipe(recipe=requested)
  }
}

///|
fn unknown_project_submodule(
  project : @semantic.ProjectCompilation,
  parent : @modulepath.ModulePath,
  requested : String,
  display : String,
) -> InvocationError {
  let names : Array[String] = []
  for path in project.module_paths() {
    if path.parent() == Some(parent) && path.components().last() is Some(name) {
      names.push(name)
    }
  }
  UnknownSubmodule(
    name=display,
    suggestion=closest_invocation_name(requested, names),
  )
}

///|
fn resolve_project_recipe(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
  start : Int,
) -> (@modulepath.ModulePath, String, Int) raise InvocationError {
  if start >= arguments.length() {
    let recipe = require_project_default_recipe(
      project,
      @modulepath.ModulePath::root(),
    )
    return (@modulepath.ModulePath::root(), recipe.name(), 0)
  }
  let requested = arguments[start]
  let root_compilation = project.root()
  if root_compilation.alias_target(requested) is Some(_) &&
    project.alias_disabled(@modulepath.ModulePath::root(), requested) {
    raise DisabledRecipe(
      name=requested,
      modules=module_names(
        project.alias_absent_modules(@modulepath.ModulePath::root(), requested),
      ),
      is_alias=true,
    )
  }
  if project.recipe_disabled(@modulepath.ModulePath::root(), requested) {
    raise DisabledRecipe(
      name=requested,
      modules=module_names(
        project.recipe_absent_modules(@modulepath.ModulePath::root(), requested),
      ),
      is_alias=false,
    )
  }
  if project.absent_module_for_reference(
      @modulepath.ModulePath::root(),
      requested,
    )
    is Some(absent) {
    raise OptionalModuleAbsent(module_path=absent.as_string())
  }
  if requested.contains(":") {
    if requested.has_suffix("::") && start + 1 < arguments.length() {
      raise UnknownRecipe(recipe=requested)
    }
    try @modulepath.ModulePath::parse(requested) catch {
      _ => raise UnknownRecipe(recipe=requested)
    } noraise {
      _ => ()
    }
    let components : Array[String] = requested
      .split("::")
      .map(fn(component) { component.to_owned() })
      .collect()
    let mut current = @modulepath.ModulePath::root()
    for index, component in components {
      let display = components[:index + 1].join("::")
      let is_final = index + 1 == components.length()
      if project.absent_module_for_reference(current, component) is Some(absent) {
        raise OptionalModuleAbsent(module_path=absent.as_string())
      }
      if is_final {
        match project.resolve_module(current, component) {
          Some(path) => {
            let recipe = require_project_default_recipe(project, path)
            return (path, recipe.name(), 1)
          }
          None => ()
        }
        match project.resolve_recipe(current, component) {
          Some(recipe) => {
            ensure_project_recipe_available(project, recipe, requested)
            return (recipe.module_path(), recipe.recipe_name(), 1)
          }
          None =>
            raise unknown_project_recipe(
              project.module_compilation(current).unwrap(),
              requested,
              component,
            )
        }
      }
      match project.resolve_module(current, component) {
        Some(path) => current = path
        None =>
          match project.resolve_recipe(current, component) {
            Some(_) => raise ExpectedSubmoduleFoundRecipe(path=display)
            None =>
              raise unknown_project_submodule(
                project, current, component, display,
              )
          }
      }
    }
  }
  let mut current = @modulepath.ModulePath::root()
  let mut cursor = start
  while cursor < arguments.length() {
    let component = arguments[cursor]
    match project.resolve_module(current, component) {
      Some(module_path) => {
        current = module_path
        cursor += 1
      }
      None => {
        if project.absent_module_for_reference(current, component)
          is Some(absent) {
          raise OptionalModuleAbsent(module_path=absent.as_string())
        }
        match project.resolve_recipe(current, component) {
          Some(recipe) => {
            ensure_project_recipe_available(project, recipe, component)
            return (
              recipe.module_path(),
              recipe.recipe_name(),
              cursor - start + 1,
            )
          }
          None =>
            raise unknown_project_recipe(
              project.module_compilation(current).unwrap(),
              arguments[start:cursor + 1].join(" "),
              component,
            )
        }
      }
    }
  }
  let recipe = require_project_default_recipe(project, current)
  (current, recipe.name(), cursor - start)
}

///|
/// Parse invocations across independently compiled project modules. Both
/// `module::recipe` and the upstream space-separated `module recipe` form are
/// accepted. Existing single-compilation parsing remains unchanged.
pub fn parse_project_invocations(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
  overrides? : ArrayView[(String, String)] = [],
  allow_missing? : Bool = false,
) -> Array[ProjectInvocation] raise InvocationError {
  let environments : Map[@modulepath.ModulePath, @evaluator.Environment] = Map([])
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    environments[path] = @evaluator.evaluate_compilation(
      compilation,
      overrides=project_overrides(path, overrides),
    ) catch {
      error => raise Evaluation(error)
    }
  }
  parse_project_invocations_in_environments(
    project,
    arguments,
    environments,
    allow_missing~,
  )
}

///|
/// Parse project invocations with the already materialized module scopes used
/// by execution. This prevents effectful assignments from being evaluated a
/// second time through the pure parser path.
pub fn parse_project_invocations_in_environments(
  project : @semantic.ProjectCompilation,
  arguments : ArrayView[String],
  environments : Map[@modulepath.ModulePath, @evaluator.Environment],
  allow_missing? : Bool = false,
  resolve_expressions? : Bool = true,
) -> Array[ProjectInvocation] raise InvocationError {
  let result : Array[ProjectInvocation] = []
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
    let global = environments.get(module_path).unwrap()
    let synthetic : Array[String] = [recipe]
    for value in arguments[cursor + path_consumed:] {
      synthetic.push(value)
    }
    let (invocation, consumed) = parse_one(
      compilation,
      global,
      synthetic,
      0,
      resolve_expressions~,
      display_name=arguments[cursor:cursor + path_consumed].join("::"),
    )
    result.push({ module_path, invocation, })
    cursor += path_consumed + consumed - 1
    if cursor >= arguments.length() {
      break
    }
  }
  result
}
