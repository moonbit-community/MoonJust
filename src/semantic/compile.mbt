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
/// Compile an AST into an immutable, ordered semantic model.
pub fn compile(
  ast : @syntax.Ast,
  platform? : TargetPlatform = TargetPlatform::new(Other("unknown"), false),
  allow_unstable? : Bool = false,
  defer_recipe_linking? : Bool = false,
) -> Compilation raise SemanticError {
  let preliminary_settings_nodes : Array[@syntax.Setting] = []
  let mut preliminary_attributes : Array[@syntax.Attribute] = []
  for item in ast.items() {
    match item {
      Attribute(value) => preliminary_attributes.push(value)
      Setting(value) => {
        if platform_attributes_match(preliminary_attributes, platform) {
          preliminary_settings_nodes.push(value)
        }
        preliminary_attributes = []
      }
      Assignment(_) | Function(_) | Alias(_) | Recipe(_) | Unexport(_) =>
        preliminary_attributes = []
      Comment(_) | TrailingComment(_) | Blank(_) | Import(_) | Module(_) => ()
    }
  }
  let preliminary_settings = compile_settings(preliminary_settings_nodes)
  let settings_nodes : Array[@syntax.Setting] = []
  let variables : Array[@syntax.Assignment] = []
  let functions : Array[@syntax.FunctionDefinition] = []
  let recipes : Array[@syntax.Recipe] = []
  // Keep the validated attributes aligned with recipes so later semantic
  // passes do not reparse the same attribute list.
  let recipe_attributes : Array[RecipeAttributes] = []
  let aliases : Array[@syntax.Alias] = []
  let unexports : Array[String] = []
  let symbols : Array[Symbol] = []
  let recipe_spans : Map[String, @source.Span] = Map([])
  let variable_spans : Map[String, @source.Span] = Map([])
  let function_spans : Map[String, @source.Span] = Map([])
  let alias_spans : Map[String, @source.Span] = Map([])
  let alias_names : Map[String, String] = Map([])
  let recipe_docs : Map[String, String] = Map([])
  let mut pending_docs : Array[String] = []
  let mut pending_attributes : Array[@syntax.Attribute] = []
  for item in ast.items() {
    match item {
      Setting(value) => {
        validate_item_attributes(
          "setting",
          value.name(),
          pending_attributes,
          [],
          semantic_name_span(value.span(), value.name(), offset=4),
        )
        let enabled = platform_attributes_match(pending_attributes, platform)
        pending_attributes = []
        if !enabled {
          pending_docs = []
          continue
        }
        settings_nodes.push(value)
        pending_docs = []
      }
      Attribute(value) => pending_attributes.push(value)
      Assignment(value) => {
        pending_attributes = []
        pending_docs = []
        validate_item_attributes(
          "assignment",
          value.name(),
          value.attributes(),
          ["private"],
          semantic_name_span(value.span(), value.name()),
        )
        if !value.attributes().is_empty() &&
          !compile_attributes(value.attributes()).matches(platform) {
          continue
        }
        let name = value.name()
        if variable_spans.get(name) is Some(first) &&
          !variable_spans.contains(name + "#duplicate") {
          if !bool_setting(preliminary_settings, "allow-duplicate-variables") {
            raise DuplicateVariable(
              name~,
              first~,
              second=semantic_name_span(value.span(), name),
            )
          }
          variable_spans[name + "#duplicate"] = value.span()
        } else {
          variable_spans[name] = value.span()
        }
        variables.push(value)
        symbols.push(Symbol::new(name, Variable, value.span()))
      }
      Function(value) => {
        pending_attributes = []
        pending_docs = []
        validate_item_attributes(
          "function",
          value.name(),
          value.attributes(),
          [],
          semantic_name_span(value.span(), value.name()),
        )
        if !value.attributes().is_empty() &&
          !compile_attributes(value.attributes()).matches(platform) {
          continue
        }
        let name = value.name()
        match function_spans.get(name) {
          Some(first) =>
            raise DuplicateFunction(
              name~,
              first~,
              second=semantic_name_span(value.span(), name),
            )
          None => function_spans[name] = value.span()
        }
        let parameters : Set[String] = Set([])
        for parameter in value.parameters() {
          if parameters.contains(parameter.name()) {
            raise DuplicateFunctionParameter(
              function_name=name,
              parameter=parameter.name(),
              span=parameter.span(),
            )
          }
          parameters.add(parameter.name())
        }
        functions.push(value)
        symbols.push(Symbol::new(name, Function, value.span()))
      }
      Alias(value) => {
        pending_attributes = []
        pending_docs = []
        validate_item_attributes(
          "alias",
          value.name(),
          value.attributes(),
          ["private"],
          semantic_name_span(value.span(), value.name(), offset=6),
        )
        if !value.attributes().is_empty() &&
          !compile_attributes(value.attributes()).matches(platform) {
          continue
        }
        match recipe_spans.get(value.name()) {
          Some(first) =>
            raise SymbolRedefinition(
              name=value.name(),
              first_kind="recipe",
              second_kind="alias",
              first~,
              second=semantic_name_span(value.span(), value.name(), offset=6),
            )
          None => ()
        }
        match alias_spans.get(value.name()) {
          Some(first) =>
            raise SymbolRedefinition(
              name=value.name(),
              first_kind="alias",
              second_kind="alias",
              first~,
              second=semantic_name_span(value.span(), value.name(), offset=6),
            )
          None => alias_spans[value.name()] = value.span()
        }
        alias_names[value.name()] = value.target()
        aliases.push(value)
        symbols.push(
          Symbol::new(
            value.name(),
            Alias,
            semantic_name_span(value.span(), value.name(), offset=6),
          ),
        )
      }
      Recipe(value) => {
        let name = value.name()
        if !pending_docs.is_empty() {
          recipe_docs[name] = pending_docs.join(" ")
        }
        pending_docs = []
        let attributes = if value.attributes().is_empty() {
          empty_recipe_attributes()
        } else {
          compile_attributes(
            value.attributes(),
            recipe_name=value.name(),
            recipe_span=value.span(),
          )
        }
        if !attributes.matches(platform) {
          pending_attributes = []
          continue
        }
        match alias_spans.get(name) {
          Some(first) =>
            raise SymbolRedefinition(
              name~,
              first_kind="alias",
              second_kind="recipe",
              first~,
              second=semantic_name_span(value.span(), name),
            )
          None => ()
        }
        if recipe_spans.get(name) is Some(first) &&
          !recipe_spans.contains(name + "#duplicate") {
          if !bool_setting(preliminary_settings, "allow-duplicate-recipes") {
            raise DuplicateRecipe(
              name~,
              first~,
              second=semantic_name_span(value.span(), name),
            )
          }
          recipe_spans[name + "#duplicate"] = value.span()
        } else {
          recipe_spans[name] = value.span()
        }
        validate_parameters(value)
        recipes.push(value)
        recipe_attributes.push(attributes)
        symbols.push(
          Symbol::new(name, Recipe, semantic_name_span(value.span(), name)),
        )
        pending_attributes = []
      }
      Comment(text~, ..) => {
        let trimmed = text.trim()
        if trimmed.has_prefix("# ") {
          pending_docs.push(trimmed.view(start_offset=2).to_owned())
        } else {
          pending_docs = []
        }
      }
      TrailingComment(_) => ()
      Blank(_) => pending_docs = []
      Unexport(name~, ..) => {
        validate_item_attributes(
          "unexport",
          name,
          pending_attributes,
          [],
          item.span(),
        )
        let enabled = platform_attributes_match(pending_attributes, platform)
        pending_attributes = []
        pending_docs = []
        if enabled {
          if unexports.contains(name) {
            raise DuplicateUnexport(
              variable=name,
              span=semantic_span_offsets(item.span(), 9, 9 + name.length()),
            )
          }
          unexports.push(name)
        }
      }
      Import(value) => {
        validate_item_attributes(
          "import",
          value.path().cooked(),
          pending_attributes,
          [],
          value.span(),
        )
        pending_docs = []
      }
      Module(value) => {
        validate_item_attributes(
          "module",
          value.name(),
          value.attributes(),
          ["doc", "group", "private"],
          value.name_span(),
        )
        pending_docs = []
      }
    }
  }
  let settings = compile_settings(settings_nodes)
  for variable in variables {
    if unexports.contains(variable.name()) {
      raise ExportUnexported(
        variable=variable.name(),
        span=semantic_span_offsets(
          variable.span(),
          7,
          7 + variable.name().length(),
        ),
      )
    }
  }
  if !functions.is_empty() && !allow_unstable && !settings.bool("unstable") {
    raise UserFunctionsUnstable(span=functions[0].span())
  }
  if settings.bool("lists") && !allow_unstable && !settings.bool("unstable") {
    for setting in settings_nodes {
      if setting.name() == "lists" {
        raise ListsUnstable(span=setting.span())
      }
    }
  }
  validate_minimum_version(settings, settings_nodes)
  for recipe in recipes {
    for dependency in recipe_dependencies(recipe) {
      if dependency.starred() {
        if !settings.bool("lists") {
          raise InvalidMappedDependency(
            message="mapped dependencies require `set lists`",
            span=semantic_name_span(
              dependency.span(),
              dependency.name(),
              offset=2,
            ),
          )
        }
        if dependency.starred_arguments().is_empty() {
          raise InvalidMappedDependency(
            message="mapped dependencies must have starred argument",
            span=semantic_span_offsets(dependency.span(), 0, 1),
          )
        }
        if dependency.starred_arguments().length() > 1 {
          let index = dependency.starred_arguments()[1]
          let argument_span = dependency.arguments()[index].span()
          raise InvalidMappedDependency(
            message="mapped dependencies may not have multiple starred arguments",
            span=semantic_span_offsets(argument_span, -1, 0),
          )
        }
      } else if !dependency.starred_arguments().is_empty() {
        let index = dependency.starred_arguments()[0]
        let argument_span = dependency.arguments()[index].span()
        raise InvalidMappedDependency(
          message="starred arguments may not be used outside mapped dependencies",
          span=semantic_span_offsets(argument_span, -1, 0),
        )
      }
    }
  }
  let mut saw_default_recipe = false
  for index, recipe in recipes {
    let attributes = recipe_attributes[index]
    if attributes.names().contains("default") {
      if saw_default_recipe {
        raise DuplicateDefaultAttribute(
          recipe=recipe.name(),
          span=recipe.span(),
        )
      }
      saw_default_recipe = true
    }
    let explicit_shell = attributes.names().contains("shell")
    let is_script = attributes.script() ||
      (
        !explicit_shell &&
        (settings.bool("default-script") || semantic_recipe_has_shebang(recipe))
      )
    let script_attribute = if attributes.extension() is Some(_) {
      Some("extension")
    } else if attributes.names().contains("cache") {
      Some("cache")
    } else {
      None
    }
    if script_attribute is Some(attribute) && !is_script {
      raise ScriptAttributeOnShellRecipe(
        recipe=recipe.name(),
        attribute~,
        span=semantic_name_span(recipe.span(), recipe.name()),
      )
    }
    if !is_script {
      validate_shell_recipe_indentation(recipe)
    }
  }
  let recipe_map : Map[String, @syntax.Recipe] = Map([])
  for recipe in recipes {
    recipe_map[recipe.name()] = recipe
  }
  if !defer_recipe_linking {
    for definition in aliases {
      validate_alias(definition, alias_names, recipe_map)
    }
  }
  let variable_names : Set[String] = Set([])
  let const_variables : Set[String] = Set([])
  for
    name in [
      "HEX", "HEXLOWER", "HEXUPPER", "PATH_SEP", "PATH_VAR_SEP", "CLEAR", "NORMAL",
      "BOLD", "ITALIC", "UNDERLINE", "INVERT", "HIDE", "STRIKETHROUGH", "BLACK",
      "RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN", "WHITE", "BG_BLACK", "BG_RED",
      "BG_GREEN", "BG_YELLOW", "BG_BLUE", "BG_MAGENTA", "BG_CYAN", "BG_WHITE",
    ] {
    variable_names.add(name)
    const_variables.add(name)
  }
  for variable in variables {
    variable_names.add(variable.name())
    const_variables.remove(variable.name())
  }
  let mut const_changed = true
  while const_changed {
    const_changed = false
    for variable in variables {
      if !const_variables.contains(variable.name()) &&
        expression_is_const(variable.value(), const_variables) {
        const_variables.add(variable.name())
        const_changed = true
      }
    }
  }
  let function_map : Map[String, @syntax.FunctionDefinition] = Map([])
  for definition in functions {
    function_map[definition.name()] = definition
  }
  for definition in functions {
    let locals : Set[String] = Set([])
    for parameter in definition.parameters() {
      locals.add(parameter.name())
    }
    validate_expression_semantics(
      definition.body(),
      variable_names,
      locals,
      function_map,
    )
    validate_list_mode_expression(definition.body(), settings.bool("lists"))
  }
  for setting in settings_nodes {
    match setting.value() {
      Some(value) =>
        validate_expression_semantics(
          value,
          variable_names,
          Set([]),
          function_map,
        )
      None => ()
    }
  }
  for recipe in recipes {
    if recipe.parameters().is_empty() &&
      recipe.dependencies().is_empty() &&
      recipe.subsequent_dependencies().is_empty() &&
      recipe.lines().is_empty() &&
      recipe.attributes().is_empty() {
      continue
    }
    validate_recipe_sigils(
      recipe,
      settings.bool("guards"),
      settings.bool("ignore-comments"),
    )
    validate_recipe_expressions(
      recipe,
      variable_names,
      const_variables,
      function_map,
      settings.bool("ignore-comments"),
    )
  }
  for variable in variables {
    validate_list_mode_expression(variable.value(), settings.bool("lists"))
    validate_expression_semantics(
      variable.value(),
      variable_names,
      Set([]),
      function_map,
    )
  }
  if !defer_recipe_linking {
    let states : Map[String, Int] = Map([])
    for recipe in recipes {
      if recipe.dependencies().is_empty() &&
        recipe.subsequent_dependencies().is_empty() {
        states[recipe.name()] = 2
      } else {
        validate_dependency_graph(
          recipe,
          recipe_map,
          alias_names,
          states,
          settings.bool("lists"),
        )
      }
    }
  }
  let attribute_map : Map[String, RecipeAttributes] = Map([])
  for index, recipe in recipes {
    attribute_map[recipe.name()] = recipe_attributes[index]
  }
  let ordered_variable_names : Array[String] = []
  let variable_map : Map[String, @syntax.Assignment] = Map([])
  let variable_name_set : Set[String] = Set([])
  for value in variables {
    variable_map[value.name()] = value
    if !variable_name_set.contains(value.name()) {
      variable_name_set.add(value.name())
      ordered_variable_names.push(value.name())
    }
  }
  let ordered_function_names = functions.map(fn(value) { value.name() })
  let ordered_recipe_names : Array[String] = []
  let recipe_name_set : Set[String] = Set([])
  for value in recipes {
    if !recipe_name_set.contains(value.name()) {
      recipe_name_set.add(value.name())
      ordered_recipe_names.push(value.name())
    }
  }
  {
    source_id: ast.source_id(),
    settings,
    symbols,
    variables,
    variable_names: ordered_variable_names,
    variable_map,
    functions,
    function_names: ordered_function_names,
    function_map,
    recipes,
    recipe_names: ordered_recipe_names,
    recipe_map,
    aliases,
    alias_targets: alias_names,
    unexports,
    attributes: attribute_map,
    recipe_docs,
  }
}

///|
/// Parse and compile source in one target-independent operation.
pub fn compile_source(
  source : @source.Source,
  allow_unstable? : Bool = false,
) -> Compilation raise SemanticError {
  let ast = @parser.parse(source) catch { error => raise Parse(error) }
  compile(ast, allow_unstable~)
}
