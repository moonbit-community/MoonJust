///|
fn compile_full(
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
  let recipe_map : Map[String, @syntax.Recipe] = Map([])
  let ordered_recipe_names : Array[String] = []
  let attribute_map : Map[String, RecipeAttributes] = Map([])
  // Keep the validated attributes aligned with recipes so later semantic
  // passes do not reparse the same attribute list.
  let recipe_attributes : Array[RecipeAttributes] = []
  let aliases : Array[@syntax.Alias] = []
  let unexports : Array[String] = []
  let symbols : Array[Symbol] = []
  let duplicate_recipe_names : Set[String] = Set([])
  let variable_spans : Map[String, @source.Span] = Map([])
  let function_spans : Map[String, @source.Span] = Map([])
  let alias_spans : Map[String, @source.Span] = Map([])
  let alias_names : Map[String, String] = Map([])
  let recipe_docs : Map[String, String] = Map([])
  let mut recipes_have_dependencies = false
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
        match recipe_map.get(value.name()) {
          Some(first_recipe) =>
            raise SymbolRedefinition(
              name=value.name(),
              first_kind="recipe",
              second_kind="alias",
              first=first_recipe.span(),
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
        let first_definition = recipe_map.get(name) is None
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
        if recipe_map.get(name) is Some(first_recipe) &&
          !duplicate_recipe_names.contains(name) {
          if !bool_setting(preliminary_settings, "allow-duplicate-recipes") {
            raise DuplicateRecipe(
              name~,
              first=first_recipe.span(),
              second=semantic_name_span(value.span(), name),
            )
          }
          duplicate_recipe_names.add(name)
        }
        validate_parameters(value)
        if !value.dependencies().is_empty() ||
          !value.subsequent_dependencies().is_empty() {
          recipes_have_dependencies = true
        }
        recipes.push(value)
        recipe_attributes.push(attributes)
        recipe_map[name] = value
        attribute_map[name] = attributes
        if first_definition {
          ordered_recipe_names.push(name)
        }
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
  if recipes_have_dependencies {
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
  if !defer_recipe_linking && recipes_have_dependencies {
    let states : Map[String, Int] = Map([])
    for recipe in recipes {
      if !recipe.dependencies().is_empty() ||
        !recipe.subsequent_dependencies().is_empty() {
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
