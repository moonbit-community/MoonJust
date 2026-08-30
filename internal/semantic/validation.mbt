///|
pub struct Compilation {
  source_id : @source.SourceId
  settings : CompiledSettings
  symbols : Array[Symbol]
  variables : Array[@syntax.Assignment]
  variable_names : Array[String]
  variable_map : Map[String, @syntax.Assignment]
  functions : Array[@syntax.FunctionDefinition]
  function_names : Array[String]
  function_map : Map[String, @syntax.FunctionDefinition]
  recipes : Array[@syntax.Recipe]
  recipe_names : Array[String]
  recipe_map : Map[String, @syntax.Recipe]
  aliases : Array[@syntax.Alias]
  alias_targets : Map[String, String]
  unexports : Array[String]
  attributes : Map[String, RecipeAttributes]
  recipe_docs : Map[String, String]
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
  self.variable_names[:]
}

///|
pub fn Compilation::function_names(self : Compilation) -> ArrayView[String] {
  self.function_names[:]
}

///|
pub fn Compilation::function(
  self : Compilation,
  name : String,
) -> @syntax.FunctionDefinition? {
  self.function_map.get(name)
}

///|
pub fn Compilation::recipe_names(self : Compilation) -> ArrayView[String] {
  self.recipe_names[:]
}

///|
pub fn Compilation::recipe(
  self : Compilation,
  name : String,
) -> @syntax.Recipe? {
  self.recipe_map.get(name)
}

///|
pub fn Compilation::variable(
  self : Compilation,
  name : String,
) -> @syntax.Assignment? {
  self.variable_map.get(name)
}

///|
pub fn Compilation::alias_target(self : Compilation, name : String) -> String? {
  self.alias_targets.get(name)
}

///|
pub fn Compilation::alias_private(self : Compilation, name : String) -> Bool {
  for definition in self.aliases {
    if definition.name() == name {
      return definition
        .attributes()
        .any(fn(attribute) { attribute.name() == "private" })
    }
  }
  false
}

///|
pub fn Compilation::unexports(self : Compilation) -> ArrayView[String] {
  self.unexports[:]
}

///|
pub fn Compilation::recipe_attributes(
  self : Compilation,
  name : String,
) -> RecipeAttributes? {
  self.attributes.get(name)
}

///|
pub fn Compilation::recipe_doc(self : Compilation, name : String) -> String? {
  match self.attributes.get(name) {
    Some(attributes) if attributes.names().contains("doc") => attributes.doc()
    _ => self.recipe_docs.get(name)
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
  let mut definition : @syntax.Setting? = None
  for node in setting_nodes {
    if node.name() == "minimum-version" {
      definition = Some(node)
    }
  }
  match settings.get("minimum-version") {
    Some(Text(required)) =>
      match version_parts(required) {
        Some(requested) if version_greater(requested, (1, 57, 0)) => {
          let span = match definition.unwrap().value() {
            Some(String(value)) => value.span()
            _ => definition.unwrap().span()
          }
          raise MinimumVersionUnsatisfied(required~, current="1.57.0", span~)
        }
        Some(_) => ()
        None => {
          let span = match definition.unwrap().value() {
            Some(String(value)) => value.span()
            _ => definition.unwrap().span()
          }
          raise InvalidMinimumVersion(value=required, span~)
        }
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
          raise UnknownAliasTarget(
            alias_name=definition.name(),
            target=current,
            span=semantic_name_span(
              definition.span(),
              definition.name(),
              offset=6,
            ),
          )
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
  lists : Bool,
) -> Unit raise SemanticError {
  let name = recipe.name()
  match states.get(name) {
    Some(2) => return
    Some(1) => raise DependencyCycle(name~, span=recipe.span())
    _ => ()
  }
  states[name] = 1
  if recipe.dependencies().is_empty() &&
    recipe.subsequent_dependencies().is_empty() {
    states[name] = 2
    return
  }
  for dependency in recipe_dependencies(recipe) {
    let mut target = dependency.name()
    if !aliases.is_empty() {
      let alias_seen : Set[String] = Set([])
      while aliases.get(target) is Some(next) {
        if alias_seen.contains(target) {
          raise AliasCycle(name=target, span=dependency.span())
        }
        alias_seen.add(target)
        target = next
      }
    }
    match recipes.get(target) {
      None =>
        raise UnknownDependency(
          recipe=recipe.name(),
          target~,
          span=semantic_name_span(dependency.span(), dependency.name()),
        )
      Some(next_recipe) => {
        if states.get(target) == Some(1) {
          raise DependencyCycle(name=recipe.name(), span=dependency.span())
        }
        let actual = dependency.arguments().length()
        let parameters = next_recipe.parameters()
        if parameters.is_empty() {
          if actual != 0 {
            raise InvalidDependencyArguments(
              name=target,
              expected="0",
              actual~,
              span=dependency.name_span(),
            )
          }
        } else {
          let flag_parameters = recipe_flag_parameter_names(next_recipe)
          let mut required = 0
          let mut maximum = 0
          for parameter in parameters {
            if flag_parameters.contains(parameter.name()) {
              continue
            }
            maximum += 1
            if parameter.variadic() {
              required += parameter.variadic_minimum()
            } else if parameter.default_value() is None {
              required += 1
            }
          }
          let has_variadic = parameters.any(fn(parameter) {
            parameter.variadic()
          })
          if actual < required || (actual > maximum && (!has_variadic || lists)) {
            let expected = if required == maximum && !has_variadic {
              required.to_string()
            } else if actual > maximum {
              "at most " + maximum.to_string()
            } else {
              "at least " + required.to_string()
            }
            raise InvalidDependencyArguments(
              name=target,
              expected~,
              actual~,
              span=dependency.name_span(),
            )
          }
        }
        validate_dependency_graph(next_recipe, recipes, aliases, states, lists)
      }
    }
  }
  states[name] = 2
}

///|
fn recipe_option_parameter_names(recipe : @syntax.Recipe) -> Set[String] {
  let result : Set[String] = Set([])
  for attribute in recipe.attributes() {
    if attribute.name() != "arg" {
      continue
    }
    guard attribute.arguments().get(0) is Some(first) else { continue }
    guard first.value() is Some(String(name)) else { continue }
    for argument in attribute.arguments()[1:] {
      match argument.key() {
        Some("long") | Some("short") => result.add(name.cooked())
        _ => ()
      }
    }
  }
  result
}

///|
fn recipe_flag_parameter_names(recipe : @syntax.Recipe) -> Set[String] {
  let result : Set[String] = Set([])
  for attribute in recipe.attributes() {
    if attribute.name() != "arg" {
      continue
    }
    guard attribute.arguments().get(0) is Some(first) else { continue }
    guard first.value() is Some(String(name)) else { continue }
    for argument in attribute.arguments()[1:] {
      if argument.key() == Some("flag") {
        result.add(name.cooked())
      }
    }
  }
  result
}

///|
fn validate_item_attributes(
  item_kind : String,
  item_name : String,
  attributes : ArrayView[@syntax.Attribute],
  allowed : ArrayView[String],
  span : @source.Span,
) -> Unit raise SemanticError {
  for attribute in attributes {
    if platform_for(attribute.name()) is None &&
      !allowed.contains(attribute.name()) {
      raise InvalidItemAttribute(
        item_kind~,
        item_name~,
        attribute=attribute.name(),
        span~,
      )
    }
  }
}

///|
fn semantic_name_span(
  span : @source.Span,
  name : String,
  offset? : Int = 0,
) -> @source.Span {
  @source.Span::new(
    span.source_id(),
    span.start_byte() + offset,
    span.start_byte() + offset + name.length(),
  ) catch {
    _ => span
  }
}

///|
fn semantic_span_offsets(
  span : @source.Span,
  start_offset : Int,
  end_offset : Int,
) -> @source.Span {
  @source.Span::new(
    span.source_id(),
    span.start_byte() + start_offset,
    span.start_byte() + end_offset,
  ) catch {
    _ => span
  }
}

///|
fn validate_parameters(recipe : @syntax.Recipe) -> Unit raise SemanticError {
  let parameters = recipe.parameters()
  if parameters.is_empty() {
    return
  }
  let option_parameters = recipe_option_parameter_names(recipe)
  let names : Set[String] = Set([])
  let mut saw_default = false
  let mut saw_variadic = false
  for parameter in parameters {
    if names.contains(parameter.name()) {
      raise DuplicateRecipeParameter(
        recipe=recipe.name(),
        parameter=parameter.name(),
        span=parameter.span(),
      )
    }
    names.add(parameter.name())
    if option_parameters.contains(parameter.name()) {
      continue
    }
    if saw_variadic {
      raise ParameterFollowsVariadic(
        parameter=parameter.name(),
        span=parameter.span(),
      )
    }
    if saw_default && parameter.default_value() is None && !parameter.variadic() {
      raise ParameterFollowsDefault(
        parameter=parameter.name(),
        span=parameter.span(),
      )
    }
    if parameter.variadic() {
      saw_variadic = true
    }
    if parameter.default_value() is Some(_) {
      saw_default = true
    }
  }
}

///|
fn validate_expression_semantics(
  expression : @syntax.Expression,
  variables : Set[String],
  locals : Set[String],
  functions : Map[String, @syntax.FunctionDefinition],
) -> Unit raise SemanticError {
  match expression {
    Variable(name~, span~) =>
      if !variables.contains(name) && !locals.contains(name) {
        raise UndefinedVariable(name~, span~)
      }
    Call(name~, arguments~, span~) => {
      let name_span = semantic_name_span(span, name)
      match functions.get(name) {
        Some(definition) => {
          let expected = definition.parameters().length()
          if arguments.length() != expected {
            raise FunctionArgumentCount(
              name~,
              expected=expected.to_string(),
              actual=arguments.length(),
              span=name_span,
            )
          }
        }
        None if name == "assert" =>
          if arguments.length() < 1 || arguments.length() > 2 {
            raise FunctionArgumentCount(
              name~,
              expected="1 or 2",
              actual=arguments.length(),
              span=name_span,
            )
          }
        None =>
          match @builtin.find(name) {
            Some(spec) =>
              if !spec.accepts_arity(arguments.length()) {
                raise FunctionArgumentCount(
                  name~,
                  expected=spec.arity_description(),
                  actual=arguments.length(),
                  span=name_span,
                )
              }
            None => raise UndefinedFunction(name~, span=name_span)
          }
      }
      for argument in arguments {
        validate_expression_semantics(argument, variables, locals, functions)
      }
    }
    List(elements~, ..) =>
      for element in elements {
        validate_expression_semantics(element, variables, locals, functions)
      }
    Parenthesized(expression~, ..) =>
      validate_expression_semantics(expression, variables, locals, functions)
    Unary(operand~, ..) =>
      validate_expression_semantics(operand, variables, locals, functions)
    Binary(lhs~, rhs~, ..) => {
      validate_expression_semantics(lhs, variables, locals, functions)
      validate_expression_semantics(rhs, variables, locals, functions)
    }
    Conditional(condition~, then_branch~, else_branch~, ..) => {
      validate_expression_semantics(condition, variables, locals, functions)
      validate_expression_semantics(then_branch, variables, locals, functions)
      match else_branch {
        Some(value) =>
          validate_expression_semantics(value, variables, locals, functions)
        None => ()
      }
    }
    Format(parts~, ..) =>
      for part in parts {
        validate_expression_semantics(
          part.expression(),
          variables,
          locals,
          functions,
        )
      }
    String(_) | Backtick(_) | Boolean(_) => ()
  }
}

///|
fn comparison_condition(expression : @syntax.Expression) -> Bool {
  match expression {
    Binary(operator=Equal | NotEqual | RegexMatch | RegexNotMatch, ..) => true
    Binary(operator=And | Or, lhs~, rhs~, ..) =>
      comparison_condition(lhs) && comparison_condition(rhs)
    Parenthesized(expression~, ..) => comparison_condition(expression)
    _ => false
  }
}

///|
fn expression_prefix_span(span : @source.Span, width : Int) -> @source.Span {
  @source.Span::new(
    span.source_id(),
    span.start_byte(),
    span.start_byte() + width,
  ) catch {
    _ => span
  }
}

///|
fn validate_list_mode_expression(
  expression : @syntax.Expression,
  lists : Bool,
  comparison_allowed? : Bool = false,
) -> Unit raise SemanticError {
  if lists {
    return
  }
  match expression {
    List(span~, ..) =>
      raise ListsFeature(
        message="list literals require `set lists`",
        span=expression_prefix_span(span, 1),
      )
    Boolean(span~, ..) =>
      raise ListsFeature(message="boolean values require `set lists`", span~)
    Unary(operand~, span~, ..) => {
      raise ListsFeature(
        message="negation operator requires `set lists`",
        span=expression_prefix_span(span, 1),
      )
      validate_list_mode_expression(operand, lists)
    }
    Binary(operator~, operator_span~, lhs~, rhs~, ..) => {
      match operator {
        Equal | NotEqual | RegexMatch | RegexNotMatch if !comparison_allowed =>
          raise ListsFeature(
            message="comparison operators require `set lists`",
            span=operator_span,
          )
        And | Or =>
          raise ListsFeature(
            message="logical operators require `set lists`",
            span=operator_span,
          )
        ListConcat =>
          raise ListsFeature(
            message="list concatenation operator `++` requires `set lists`",
            span=operator_span,
          )
        _ => ()
      }
      validate_list_mode_expression(lhs, lists)
      validate_list_mode_expression(rhs, lists)
    }
    Conditional(condition~, then_branch~, else_branch~, span~) => {
      if else_branch is None {
        raise ListsFeature(
          message="`if` without `else` requires `set lists`",
          span=expression_prefix_span(span, 2),
        )
      }
      if !comparison_condition(condition) {
        raise ListsFeature(
          message="`if` and `assert` conditions other than comparisons require `set lists`",
          span=match condition {
            Call(name~, span~, ..) =>
              expression_prefix_span(span, name.length())
            _ => condition.span()
          },
        )
      }
      validate_list_mode_expression(condition, lists, comparison_allowed=true)
      validate_list_mode_expression(then_branch, lists)
      match else_branch {
        Some(value) => validate_list_mode_expression(value, lists)
        None => ()
      }
    }
    Call(name="assert", arguments~, ..) =>
      for index, argument in arguments {
        validate_list_mode_expression(
          argument,
          lists,
          comparison_allowed=index == 0,
        )
      }
    Call(arguments~, ..) =>
      for argument in arguments {
        validate_list_mode_expression(argument, lists)
      }
    Parenthesized(expression~, ..) =>
      validate_list_mode_expression(expression, lists, comparison_allowed~)
    Format(parts~, ..) =>
      for part in parts {
        validate_list_mode_expression(part.expression(), lists)
      }
    String(_) | Backtick(_) | Variable(_) => ()
  }
}

///|
fn expression_is_const(
  expression : @syntax.Expression,
  const_variables : Set[String],
) -> Bool {
  match expression {
    String(_) | Boolean(_) => true
    Backtick(_) => false
    Variable(name~, ..) => const_variables.contains(name)
    Call(name~, arguments~, ..) =>
      !@builtin.is_effectful(name) &&
      arguments.all(fn(argument) {
        expression_is_const(argument, const_variables)
      })
    List(elements~, ..) =>
      elements.all(fn(element) { expression_is_const(element, const_variables) })
    Parenthesized(expression~, ..) =>
      expression_is_const(expression, const_variables)
    Unary(operand~, ..) => expression_is_const(operand, const_variables)
    Binary(lhs~, rhs~, ..) =>
      expression_is_const(lhs, const_variables) &&
      expression_is_const(rhs, const_variables)
    Conditional(condition~, then_branch~, else_branch~, ..) =>
      expression_is_const(condition, const_variables) &&
      expression_is_const(then_branch, const_variables) &&
      else_branch
      .map(fn(value) { expression_is_const(value, const_variables) })
      .unwrap_or(true)
    Format(parts~, ..) =>
      parts.all(fn(part) {
        expression_is_const(part.expression(), const_variables)
      })
  }
}

///|
fn validate_const_expression(
  expression : @syntax.Expression,
  variables : Set[String],
  const_variables : Set[String],
) -> Unit raise SemanticError {
  match expression {
    Variable(name~, span~) =>
      if !variables.contains(name) {
        raise UndefinedVariable(name~, span~)
      } else if !const_variables.contains(name) {
        raise NonConstVariable(name~, span~)
      }
    Backtick(literal) =>
      raise ConstContext(kind="backticks", span=literal.span())
    Call(name="assert", arguments~, ..) | List(elements=arguments, ..) =>
      for argument in arguments {
        validate_const_expression(argument, variables, const_variables)
      }
    Call(name~, span~, ..) =>
      raise ConstContext(
        kind="functions",
        span=expression_prefix_span(span, name.length()),
      )
    Parenthesized(expression~, ..) | Unary(operand=expression, ..) =>
      validate_const_expression(expression, variables, const_variables)
    Binary(lhs~, rhs~, ..) => {
      validate_const_expression(lhs, variables, const_variables)
      validate_const_expression(rhs, variables, const_variables)
    }
    Conditional(condition~, then_branch~, else_branch~, ..) => {
      validate_const_expression(condition, variables, const_variables)
      validate_const_expression(then_branch, variables, const_variables)
      match else_branch {
        Some(value) =>
          validate_const_expression(value, variables, const_variables)
        None => ()
      }
    }
    Format(parts~, ..) =>
      for part in parts {
        validate_const_expression(part.expression(), variables, const_variables)
      }
    String(_) | Boolean(_) => ()
  }
}

///|
