///|
/// A module source in analyzer visitation order. Its items retain lexical order.
pub(all) struct ImportSource {
  source : @source.Source
  depth : Int32
  items : ArrayView[@syntax.Item]
}

///|
#derive(Eq, Hash)
priv enum DeclarationName {
  Alias(String)
  Recipe(String)
  Variable(String)
}

///|
priv struct Definition {
  span : @source.Span
  source : @source.Source?
  depth : Int32
}

///|
fn redefinition_spans(
  previous : Definition,
  current : Definition,
) -> (@source.Span, @source.Span) {
  // just compares line numbers even when they belong to different files.
  // On a tie the second declaration visited gets the primary diagnostic.
  if previous.source is Some(a) &&
    current.source is Some(b) &&
    previous.span.source_id() != current.span.source_id() &&
    (try! a.locate(previous.span.start_byte())).line() >
    (try! b.locate(current.span.start_byte())).line() {
    (current.span, previous.span)
  } else {
    (previous.span, current.span)
  }
}

///|
fn shadowed_declarations(
  ast : @syntax.Ast,
  imports : ArrayView[ImportSource],
  platform : TargetPlatform,
  settings : CompiledSettings,
) -> Set[@source.Span] raise SemanticError {
  let winners : Map[DeclarationName, Definition] = Map([])
  let shadowed = Set([])
  let allow_variables = bool_setting(settings, "allow-duplicate-variables")
  let allow_recipes = bool_setting(settings, "allow-duplicate-recipes")
  let mut variable_error : SemanticError? = None
  let mut recipe_error : SemanticError? = None
  fn visit(
    items : ArrayView[@syntax.Item],
    source : @source.Source?,
    depth : Int32,
  ) -> Unit raise SemanticError {
    for item in items {
      let (key, span) : (DeclarationName, @source.Span) = match item {
        Recipe(r) if platform_attributes_match(r.attributes(), platform) =>
          (Recipe(r.name()), r.name_span)
        Assignment(v) if platform_attributes_match(v.attributes(), platform) =>
          (Variable(v.name()), v.name_span)
        Alias(a) if platform_attributes_match(a.attributes(), platform) =>
          (Alias(a.name()), a.name_span)
        _ => continue
      }
      let current = { source, span, depth, }
      guard winners.get(key) is Some(previous) else {
        winners[key] = current
        continue
      }
      match key {
        Alias(name) => {
          let (first, second) = redefinition_spans(previous, current)
          raise SymbolRedefinition(
            name~,
            first_kind="alias",
            second_kind="alias",
            first~,
            second~,
          )
        }
        Variable(name) if !allow_variables =>
          if variable_error is None {
            variable_error = Some(
              DuplicateVariable(name~, first=previous.span, second=span),
            )
          }
        Recipe(name) if !allow_recipes =>
          if recipe_error is None {
            let (first, second) = redefinition_spans(previous, current)
            recipe_error = Some(DuplicateRecipe(name~, first~, second~))
          }
        _ if depth <= previous.depth => {
          shadowed.add(previous.span)
          winners[key] = current
        }
        _ => shadowed.add(span)
      }
    }
  }
  if imports.is_empty() {
    visit(ast.items(), None, 0)
  } else {
    for file in imports {
      visit(file.items, Some(file.source), file.depth)
    }
  }
  // Upstream defines aliases during the walk, then variables, then recipes.
  if variable_error is Some(error) {
    raise error
  }
  if recipe_error is Some(error) {
    raise error
  }
  shadowed
}
