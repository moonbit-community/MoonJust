///|
fn compile_plain_empty_recipes(
  ast : @syntax.Ast,
) -> Compilation? raise SemanticError {
  let recipes : Array[@syntax.Recipe] = []
  let recipe_names : Array[String] = []
  let recipe_map : Map[String, @syntax.Recipe] = Map([])
  let attributes : Map[String, RecipeAttributes] = Map([])
  let symbols : Array[Symbol] = []
  for item in ast.items() {
    match item {
      Recipe(recipe) if recipe.parameters().is_empty() &&
        recipe.dependencies().is_empty() &&
        recipe.subsequent_dependencies().is_empty() &&
        recipe.lines().is_empty() &&
        recipe.attributes().is_empty() => {
        let name = recipe.name()
        match recipe_map.get(name) {
          Some(first) =>
            raise DuplicateRecipe(
              name~,
              first=first.span(),
              second=semantic_name_span(recipe.span(), name),
            )
          None => ()
        }
        recipes.push(recipe)
        recipe_names.push(name)
        recipe_map[name] = recipe
        attributes[name] = empty_recipe_attributes()
        symbols.push(
          Symbol::new(name, Recipe, semantic_name_span(recipe.span(), name)),
        )
      }
      Blank(_) | TrailingComment(_) => ()
      _ => return None
    }
  }
  Some({
    source_id: ast.source_id(),
    settings: empty_compiled_settings(),
    symbols,
    variables: [],
    variable_names: [],
    variable_map: Map([]),
    functions: [],
    function_names: [],
    function_map: Map([]),
    recipes,
    recipe_names,
    recipe_map,
    aliases: [],
    alias_targets: Map([]),
    unexports: [],
    attributes,
    recipe_docs: Map([]),
  })
}

///|
/// Compile an AST into an immutable, ordered semantic model.
pub fn compile(
  ast : @syntax.Ast,
  platform? : TargetPlatform = TargetPlatform::new(Other("unknown"), false),
  allow_unstable? : Bool = false,
  defer_recipe_linking? : Bool = false,
) -> Compilation raise SemanticError {
  match compile_plain_empty_recipes(ast) {
    Some(compilation) => return compilation
    None => ()
  }
  compile_full(ast, platform~, allow_unstable~, defer_recipe_linking~)
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
