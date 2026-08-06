///|
pub struct Compilation {
  source_id : @source.SourceId
  settings : CompiledSettings
  symbols : Array[Symbol]
  variables : Array[@syntax.Assignment]
  recipes : Array[@syntax.Recipe]
  aliases : Array[@syntax.Alias]
  attributes : Map[String, RecipeAttributes]
} derive(Debug)

///|
pub fn Compilation::source_id(self : Compilation) -> @source.SourceId {
  self.source_id
}

///|
pub fn Compilation::settings(self : Compilation) -> CompiledSettings {
  self.settings
}

///|
pub fn Compilation::symbols(self : Compilation) -> ArrayView[Symbol] {
  self.symbols[:]
}

///|
pub fn Compilation::variable_names(self : Compilation) -> ArrayView[String] {
  self.variables.map(fn(value) { value.name() })[:]
}

///|
pub fn Compilation::recipe_names(self : Compilation) -> ArrayView[String] {
  self.recipes.map(fn(value) { value.name() })[:]
}

///|
pub fn Compilation::recipe(
  self : Compilation,
  name : String,
) -> @syntax.Recipe? {
  for recipe in self.recipes {
    if recipe.name() == name && self.attributes.get(name) is Some(_) {
      return Some(recipe)
    }
  }
  None
}

///|
pub fn Compilation::variable(
  self : Compilation,
  name : String,
) -> @syntax.Assignment? {
  for variable in self.variables {
    if variable.name() == name {
      return Some(variable)
    }
  }
  None
}

///|
pub fn Compilation::alias_target(self : Compilation, name : String) -> String? {
  for definition in self.aliases {
    if definition.name() == name {
      return Some(definition.target())
    }
  }
  None
}

///|
pub fn Compilation::recipe_attributes(
  self : Compilation,
  name : String,
) -> RecipeAttributes? {
  self.attributes.get(name)
}

///|
fn expression_variables(
  expression : @syntax.Expression,
  result : Array[String],
) -> Unit {
  match expression {
    Variable(name~, ..) => result.push(name)
    Call(arguments~, ..) =>
      for argument in arguments {
        expression_variables(argument, result)
      }
    List(elements~, ..) =>
      for element in elements {
        expression_variables(element, result)
      }
    Unary(operand~, ..) => expression_variables(operand, result)
    Binary(lhs~, rhs~, ..) => {
      expression_variables(lhs, result)
      expression_variables(rhs, result)
    }
    Conditional(condition~, then_branch~, else_branch~, ..) => {
      expression_variables(condition, result)
      expression_variables(then_branch, result)
      match else_branch {
        Some(value) => expression_variables(value, result)
        None => ()
      }
    }
    Format(start~, parts~, ..) => {
      for part in parts {
        expression_variables(part.expression(), result)
      }
      ignore(start)
    }
    String(_) | Backtick(_) | Boolean(_) => ()
  }
}

///|
fn bool_setting(settings : CompiledSettings, name : String) -> Bool {
  settings.bool(name)
}

///|
fn recipe_dependencies(
  recipe : @syntax.Recipe,
) -> ArrayView[@syntax.Dependency] {
  let result : Array[@syntax.Dependency] = []
  for dependency in recipe.dependencies() {
    result.push(dependency)
  }
  for dependency in recipe.subsequent_dependencies() {
    result.push(dependency)
  }
  result[:]
}

///|
fn version_parts(value : String) -> (Int, Int, Int)? {
  let text = value.trim()
  let numbers : Array[Int] = [0, 0, 0]
  let mut part = 0
  let mut number = 0
  let mut has_digit = false
  for character in text {
    if character == '.' {
      if part >= 2 || !has_digit {
        return None
      }
      numbers[part] = number
      part += 1
      number = 0
      has_digit = false
    } else if character.is_ascii_digit() {
      number = number * 10 + character.to_int() - 48
      has_digit = true
    } else {
      return None
    }
  }
  if part != 2 || !has_digit {
    return None
  }
  numbers[2] = number
  Some((numbers[0], numbers[1], numbers[2]))
}

///|
fn version_greater(left : (Int, Int, Int), right : (Int, Int, Int)) -> Bool {
  if left.0 != right.0 {
    return left.0 > right.0
  }
  if left.1 != right.1 {
    return left.1 > right.1
  }
  left.2 > right.2
}

///|
fn validate_minimum_version(
  settings : CompiledSettings,
  setting_nodes : Array[@syntax.Setting],
) -> Unit raise SemanticError {
  match settings.get("minimum-version") {
    Some(Text(required)) =>
      match version_parts(required) {
        Some(requested) if version_greater(requested, (1, 57, 0)) => {
          let span = setting_nodes[setting_nodes.length() - 1].span()
          raise MinimumVersionUnsatisfied(required~, current="1.57.0", span~)
        }
        _ => ()
      }
    _ => ()
  }
}

///|
fn validate_alias(
  definition : @syntax.Alias,
  alias_names : Map[String, String],
  recipes : Map[String, @syntax.Recipe],
) -> Unit raise SemanticError {
  let seen : Set[String] = Set([])
  let mut current = definition.name()
  while true {
    if seen.contains(current) {
      raise AliasCycle(name=current, span=definition.span())
    }
    seen.add(current)
    match alias_names.get(current) {
      Some(next) => current = next
      None => {
        if !recipes.contains(current) {
          raise UndefinedRecipe(name=current, span=definition.span())
        }
        return
      }
    }
  }
}

///|
fn validate_dependency_graph(
  recipe : @syntax.Recipe,
  recipes : Map[String, @syntax.Recipe],
  aliases : Map[String, String],
  states : Map[String, Int],
) -> Unit raise SemanticError {
  let name = recipe.name()
  match states.get(name) {
    Some(2) => return
    Some(1) => raise DependencyCycle(name~, span=recipe.span())
    _ => ()
  }
  states[name] = 1
  for dependency in recipe_dependencies(recipe) {
    let mut target = dependency.name()
    let alias_seen : Set[String] = Set([])
    while aliases.get(target) is Some(next) {
      if alias_seen.contains(target) {
        raise AliasCycle(name=target, span=dependency.span())
      }
      alias_seen.add(target)
      target = next
    }
    match recipes.get(target) {
      None => raise UndefinedRecipe(name=target, span=dependency.span())
      Some(next_recipe) => {
        let parameters = next_recipe.parameters()
        let mut required = 0
        let mut variadic = false
        for parameter in parameters {
          if parameter.variadic() {
            variadic = true
            required += parameter.variadic_minimum()
          } else if parameter.default_value() is None {
            required += 1
          }
        }
        let actual = dependency.arguments().length()
        if actual < required || (!variadic && actual > parameters.length()) {
          let expected = if variadic {
            "at least " + required.to_string()
          } else {
            required.to_string() + ".." + parameters.length().to_string()
          }
          raise InvalidDependencyArguments(
            name=target,
            expected~,
            actual~,
            span=dependency.span(),
          )
        }
        validate_dependency_graph(next_recipe, recipes, aliases, states)
      }
    }
  }
  states[name] = 2
}

///|
fn validate_parameters(recipe : @syntax.Recipe) -> Unit raise SemanticError {
  let parameters = recipe.parameters()
  let names : Set[String] = Set([])
  let mut saw_default = false
  let mut saw_variadic = false
  for parameter in parameters {
    if names.contains(parameter.name()) {
      raise InvalidParameters(name=recipe.name(), span=parameter.span())
    }
    names.add(parameter.name())
    if saw_variadic || (saw_default && parameter.default_value() is None) {
      raise InvalidParameters(name=recipe.name(), span=parameter.span())
    }
    if parameter.variadic() {
      if parameter.default_value() is Some(_) {
        raise InvalidParameters(name=recipe.name(), span=parameter.span())
      }
      saw_variadic = true
    }
    if parameter.default_value() is Some(_) {
      saw_default = true
    }
  }
}

///|
fn recipe_expression_variables(
  recipe : @syntax.Recipe,
  result : Array[String],
) -> Unit {
  for parameter in recipe.parameters() {
    match parameter.default_value() {
      Some(value) => expression_variables(value, result)
      None => ()
    }
  }
  for dependency in recipe.dependencies() {
    for argument in dependency.arguments() {
      expression_variables(argument, result)
    }
  }
  for dependency in recipe.subsequent_dependencies() {
    for argument in dependency.arguments() {
      expression_variables(argument, result)
    }
  }
  for line in recipe.lines() {
    for fragment in line.fragments() {
      match fragment {
        Interpolation(expression~, ..) =>
          expression_variables(expression, result)
        Text(_) => ()
      }
    }
  }
  for attribute in recipe.attributes() {
    for argument in attribute.arguments() {
      match argument.value() {
        Some(value) => expression_variables(value, result)
        None => ()
      }
    }
  }
}

///|
/// Compile an AST into an immutable, ordered semantic model.
pub fn compile(
  ast : @syntax.Ast,
  platform? : TargetPlatform = TargetPlatform::new(Other("unknown"), false),
) -> Compilation raise SemanticError {
  let settings_nodes : Array[@syntax.Setting] = []
  let variables : Array[@syntax.Assignment] = []
  let recipes : Array[@syntax.Recipe] = []
  let aliases : Array[@syntax.Alias] = []
  let symbols : Array[Symbol] = []
  let recipe_spans : Map[String, @source.Span] = Map([])
  let variable_spans : Map[String, @source.Span] = Map([])
  let alias_names : Map[String, String] = Map([])
  let mut pending_attributes : Array[@syntax.Attribute] = []
  for item in ast.items() {
    match item {
      Setting(value) => settings_nodes.push(value)
      Attribute(value) => pending_attributes.push(value)
      Assignment(value) => {
        let name = value.name()
        if variable_spans.get(name) is Some(first) &&
          !variable_spans.contains(name + "#duplicate") {
          if !bool_setting(
              compile_settings(settings_nodes),
              "allow-duplicate-variables",
            ) {
            raise DuplicateVariable(name~, first~, second=value.span())
          }
          variable_spans[name + "#duplicate"] = value.span()
        } else {
          variable_spans[name] = value.span()
        }
        variables.push(value)
        symbols.push(Symbol::new(name, Variable, value.span()))
      }
      Alias(value) => {
        alias_names[value.name()] = value.target()
        aliases.push(value)
        symbols.push(Symbol::new(value.name(), Alias, value.span()))
      }
      Recipe(value) => {
        let name = value.name()
        if recipe_spans.get(name) is Some(first) &&
          !recipe_spans.contains(name + "#duplicate") {
          if !bool_setting(
              compile_settings(settings_nodes),
              "allow-duplicate-recipes",
            ) {
            raise DuplicateRecipe(name~, first~, second=value.span())
          }
          recipe_spans[name + "#duplicate"] = value.span()
        } else {
          recipe_spans[name] = value.span()
        }
        let attributes = compile_attributes(value.attributes()) catch {
          error => raise error
        }
        if !attributes.matches(platform) {
          pending_attributes = []
          continue
        }
        validate_parameters(value)
        recipes.push(value)
        symbols.push(Symbol::new(name, Recipe, value.span()))
        pending_attributes = []
      }
      Import(_) | Module(_) => ()
      Unexport(_) | Comment(_) | Blank(_) => ()
    }
  }
  let settings = compile_settings(settings_nodes)
  validate_minimum_version(settings, settings_nodes)
  let recipe_map : Map[String, @syntax.Recipe] = Map([])
  for recipe in recipes {
    recipe_map[recipe.name()] = recipe
  }
  for definition in aliases {
    validate_alias(definition, alias_names, recipe_map)
  }
  let variable_names : Set[String] = Set([])
  for variable in variables {
    variable_names.add(variable.name())
  }
  for recipe in recipes {
    let parameter_names : Set[String] = Set([])
    for parameter in recipe.parameters() {
      parameter_names.add(parameter.name())
    }
    let references : Array[String] = []
    recipe_expression_variables(recipe, references)
    for name in references {
      if !variable_names.contains(name) && !parameter_names.contains(name) {
        raise UndefinedVariable(name~, span=recipe.span())
      }
    }
  }
  for variable in variables {
    let references : Array[String] = []
    expression_variables(variable.value(), references)
    for name in references {
      if !variable_names.contains(name) {
        raise UndefinedVariable(name~, span=variable.value().span())
      }
    }
  }
  let states : Map[String, Int] = Map([])
  for recipe in recipes {
    validate_dependency_graph(recipe, recipe_map, alias_names, states)
  }
  let attribute_map : Map[String, RecipeAttributes] = Map([])
  for recipe in recipes {
    attribute_map[recipe.name()] = compile_attributes(recipe.attributes())
  }
  {
    source_id: ast.source_id(),
    settings,
    symbols,
    variables,
    recipes,
    aliases,
    attributes: attribute_map,
  }
}

///|
/// Parse and compile source in one target-independent operation.
pub fn compile_source(
  source : @source.Source,
) -> Compilation raise SemanticError {
  let ast = @parser.parse(source) catch { error => raise Parse(error) }
  compile(ast)
}
