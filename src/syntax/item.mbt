///|
pub(all) struct Parameter {
  name : String
  default_value : Expression?
  variadic : Bool
  exported : Bool
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Parameter::new(
  name : String,
  default_value : Expression?,
  variadic : Bool,
  exported : Bool,
  span : @source.Span,
) -> Parameter {
  { name, default_value, variadic, exported, span }
}

///|
pub fn Parameter::name(self : Parameter) -> String {
  self.name
}

///|
pub fn Parameter::default_value(self : Parameter) -> Expression? {
  self.default_value
}

///|
pub fn Parameter::variadic(self : Parameter) -> Bool {
  self.variadic
}

///|
pub fn Parameter::exported(self : Parameter) -> Bool {
  self.exported
}

///|
pub fn Parameter::span(self : Parameter) -> @source.Span {
  self.span
}

///|
pub(all) struct Dependency {
  name : String
  arguments : Array[Expression]
  starred : Bool
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Dependency::new(
  name : String,
  arguments : Array[Expression],
  starred : Bool,
  span : @source.Span,
) -> Dependency {
  { name, arguments, starred, span }
}

///|
pub fn Dependency::name(self : Dependency) -> String {
  self.name
}

///|
pub fn Dependency::arguments(self : Dependency) -> ArrayView[Expression] {
  self.arguments[:]
}

///|
pub fn Dependency::starred(self : Dependency) -> Bool {
  self.starred
}

///|
pub fn Dependency::span(self : Dependency) -> @source.Span {
  self.span
}

///|
pub(all) enum RecipeFragment {
  Text(text~ : String, span~ : @source.Span)
  Interpolation(expression~ : Expression, span~ : @source.Span)
} derive(Eq, Debug)

///|
pub(all) struct RecipeLine {
  fragments : Array[RecipeFragment]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn RecipeLine::new(
  fragments : Array[RecipeFragment],
  span : @source.Span,
) -> RecipeLine {
  { fragments, span }
}

///|
pub fn RecipeLine::fragments(self : RecipeLine) -> ArrayView[RecipeFragment] {
  self.fragments[:]
}

///|
pub fn RecipeLine::span(self : RecipeLine) -> @source.Span {
  self.span
}

///|
pub(all) struct AttributeArgument {
  key : String?
  value : Expression?
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn AttributeArgument::new(
  key : String?,
  value : Expression?,
  span : @source.Span,
) -> AttributeArgument {
  { key, value, span }
}

///|
pub fn AttributeArgument::key(self : AttributeArgument) -> String? {
  self.key
}

///|
pub fn AttributeArgument::value(self : AttributeArgument) -> Expression? {
  self.value
}

///|
pub fn AttributeArgument::span(self : AttributeArgument) -> @source.Span {
  self.span
}

///|
pub(all) struct Attribute {
  name : String
  arguments : Array[AttributeArgument]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Attribute::new(
  name : String,
  arguments : Array[AttributeArgument],
  span : @source.Span,
) -> Attribute {
  { name, arguments, span }
}

///|
pub fn Attribute::name(self : Attribute) -> String {
  self.name
}

///|
pub fn Attribute::arguments(self : Attribute) -> ArrayView[AttributeArgument] {
  self.arguments[:]
}

///|
pub fn Attribute::span(self : Attribute) -> @source.Span {
  self.span
}

///|
pub(all) struct Assignment {
  name : String
  value : Expression
  exported : Bool
  eager : Bool
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Assignment::new(
  name : String,
  value : Expression,
  exported : Bool,
  eager : Bool,
  span : @source.Span,
) -> Assignment {
  { name, value, exported, eager, span }
}

///|
pub fn Assignment::name(self : Assignment) -> String {
  self.name
}

///|
pub fn Assignment::value(self : Assignment) -> Expression {
  self.value
}

///|
pub fn Assignment::exported(self : Assignment) -> Bool {
  self.exported
}

///|
pub fn Assignment::eager(self : Assignment) -> Bool {
  self.eager
}

///|
pub fn Assignment::span(self : Assignment) -> @source.Span {
  self.span
}

///|
pub(all) struct Alias {
  name : String
  target : String
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Alias::new(name : String, target : String, span : @source.Span) -> Alias {
  { name, target, span }
}

///|
pub fn Alias::name(self : Alias) -> String {
  self.name
}

///|
pub fn Alias::target(self : Alias) -> String {
  self.target
}

///|
pub fn Alias::span(self : Alias) -> @source.Span {
  self.span
}

///|
pub(all) struct Setting {
  name : String
  value : Expression?
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Setting::new(
  name : String,
  value : Expression?,
  span : @source.Span,
) -> Setting {
  { name, value, span }
}

///|
pub fn Setting::name(self : Setting) -> String {
  self.name
}

///|
pub fn Setting::value(self : Setting) -> Expression? {
  self.value
}

///|
pub fn Setting::span(self : Setting) -> @source.Span {
  self.span
}

///|
pub(all) struct Import {
  path : StringLiteral
  optional : Bool
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Import::new(
  path : StringLiteral,
  optional : Bool,
  span : @source.Span,
) -> Import {
  { path, optional, span }
}

///|
pub fn Import::path(self : Import) -> StringLiteral {
  self.path
}

///|
pub fn Import::optional(self : Import) -> Bool {
  self.optional
}

///|
pub fn Import::span(self : Import) -> @source.Span {
  self.span
}

///|
pub(all) struct Module {
  name : String
  path : StringLiteral?
  optional : Bool
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Module::new(
  name : String,
  path : StringLiteral?,
  optional : Bool,
  span : @source.Span,
) -> Module {
  { name, path, optional, span }
}

///|
pub fn Module::name(self : Module) -> String {
  self.name
}

///|
pub fn Module::path(self : Module) -> StringLiteral? {
  self.path
}

///|
pub fn Module::optional(self : Module) -> Bool {
  self.optional
}

///|
pub fn Module::span(self : Module) -> @source.Span {
  self.span
}

///|
pub(all) struct Recipe {
  name : String
  quiet : Bool
  parameters : Array[Parameter]
  dependencies : Array[Dependency]
  subsequent_dependencies : Array[Dependency]
  lines : Array[RecipeLine]
  attributes : Array[Attribute]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Recipe::new(
  name : String,
  quiet : Bool,
  parameters : Array[Parameter],
  dependencies : Array[Dependency],
  subsequent_dependencies : Array[Dependency],
  lines : Array[RecipeLine],
  attributes : Array[Attribute],
  span : @source.Span,
) -> Recipe {
  {
    name,
    quiet,
    parameters,
    dependencies,
    subsequent_dependencies,
    lines,
    attributes,
    span,
  }
}

///|
pub fn Recipe::name(self : Recipe) -> String {
  self.name
}

///|
pub fn Recipe::quiet(self : Recipe) -> Bool {
  self.quiet
}

///|
pub fn Recipe::parameters(self : Recipe) -> ArrayView[Parameter] {
  self.parameters[:]
}

///|
pub fn Recipe::dependencies(self : Recipe) -> ArrayView[Dependency] {
  self.dependencies[:]
}

///|
pub fn Recipe::subsequent_dependencies(self : Recipe) -> ArrayView[Dependency] {
  self.subsequent_dependencies[:]
}

///|
pub fn Recipe::lines(self : Recipe) -> ArrayView[RecipeLine] {
  self.lines[:]
}

///|
pub fn Recipe::attributes(self : Recipe) -> ArrayView[Attribute] {
  self.attributes[:]
}

///|
pub fn Recipe::span(self : Recipe) -> @source.Span {
  self.span
}

///|
pub(all) enum Item {
  Assignment(Assignment)
  Alias(Alias)
  Recipe(Recipe)
  Setting(Setting)
  Attribute(Attribute)
  Import(Import)
  Module(Module)
  Unexport(name~ : String, span~ : @source.Span)
  Comment(text~ : String, span~ : @source.Span)
  Blank(span~ : @source.Span)
} derive(Eq, Debug)

///|
pub fn Item::span(self : Item) -> @source.Span {
  match self {
    Assignment(item) => item.span()
    Alias(item) => item.span()
    Recipe(item) => item.span()
    Setting(item) => item.span()
    Attribute(item) => item.span()
    Import(item) => item.span()
    Module(item) => item.span()
    Unexport(span~, ..) => span
    Comment(span~, ..) => span
    Blank(span~) => span
  }
}

///|
pub fn Item::name(self : Item) -> String? {
  match self {
    Assignment(item) => Some(item.name())
    Alias(item) => Some(item.name())
    Recipe(item) => Some(item.name())
    Setting(item) => Some(item.name())
    Attribute(item) => Some(item.name())
    Unexport(name~, ..) => Some(name)
    Import(_) | Module(_) | Comment(_) | Blank(_) => None
  }
}

///|
pub(all) struct Ast {
  source_id : @source.SourceId
  items : Array[Item]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Ast::new(
  source_id : @source.SourceId,
  items : Array[Item],
  span : @source.Span,
) -> Ast {
  { source_id, items, span }
}

///|
pub fn Ast::source_id(self : Ast) -> @source.SourceId {
  self.source_id
}

///|
pub fn Ast::items(self : Ast) -> ArrayView[Item] {
  self.items[:]
}

///|
pub fn Ast::span(self : Ast) -> @source.Span {
  self.span
}
