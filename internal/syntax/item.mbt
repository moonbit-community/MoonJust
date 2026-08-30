///|
pub(all) struct Parameter {
  name : String
  default_value : Expression?
  variadic : Bool
  variadic_minimum : Int
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
  {
    name,
    default_value,
    variadic,
    variadic_minimum: if variadic {
      1
    } else {
      0
    },
    exported,
    span,
  }
}

///|
/// Construct a `*name` parameter which accepts zero or more arguments.
pub fn Parameter::new_star(
  name : String,
  exported : Bool,
  span : @source.Span,
  default_value? : Expression,
) -> Parameter {
  { name, default_value, variadic: true, variadic_minimum: 0, exported, span, }
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
pub fn Parameter::variadic_minimum(self : Parameter) -> Int {
  self.variadic_minimum
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
  name_span : @source.Span
  arguments : Array[Expression]
  starred : Bool
  starred_arguments : Array[Int]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Dependency::new(
  name : String,
  name_span : @source.Span,
  arguments : Array[Expression],
  starred : Bool,
  span : @source.Span,
  starred_arguments? : ArrayView[Int] = [],
) -> Dependency {
  {
    name,
    name_span,
    arguments,
    starred,
    starred_arguments: starred_arguments.to_owned(),
    span,
  }
}

///|
pub fn Dependency::name(self : Dependency) -> String {
  self.name
}

///|
pub fn Dependency::name_span(self : Dependency) -> @source.Span {
  self.name_span
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
pub fn Dependency::starred_arguments(self : Dependency) -> ArrayView[Int] {
  self.starred_arguments[:]
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
  source_start_line : Int
  source_end_line : Int
} derive(Eq, Debug)

///|
pub fn RecipeLine::new(
  fragments : Array[RecipeFragment],
  span : @source.Span,
  source_start_line? : Int = 1,
  source_end_line? : Int = source_start_line,
) -> RecipeLine {
  { fragments, span, source_start_line, source_end_line, }
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
pub fn RecipeLine::source_start_line(self : RecipeLine) -> Int {
  self.source_start_line
}

///|
pub fn RecipeLine::source_end_line(self : RecipeLine) -> Int {
  self.source_end_line
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
  { key, value, span, }
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
  { name, arguments, span, }
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
  attributes : Array[Attribute]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Assignment::new(
  name : String,
  value : Expression,
  exported : Bool,
  eager : Bool,
  span : @source.Span,
  attributes? : Array[Attribute] = [],
) -> Assignment {
  { name, value, exported, eager, attributes, span, }
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
pub fn Assignment::attributes(self : Assignment) -> ArrayView[Attribute] {
  self.attributes[:]
}

///|
pub fn Assignment::span(self : Assignment) -> @source.Span {
  self.span
}

///|
pub(all) struct FunctionParameter {
  name : String
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn FunctionParameter::new(
  name : String,
  span : @source.Span,
) -> FunctionParameter {
  { name, span, }
}

///|
pub fn FunctionParameter::name(self : FunctionParameter) -> String {
  self.name
}

///|
pub fn FunctionParameter::span(self : FunctionParameter) -> @source.Span {
  self.span
}

///|
pub(all) struct FunctionDefinition {
  name : String
  parameters : Array[FunctionParameter]
  body : Expression
  attributes : Array[Attribute]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn FunctionDefinition::new(
  name : String,
  parameters : Array[FunctionParameter],
  body : Expression,
  attributes : Array[Attribute],
  span : @source.Span,
) -> FunctionDefinition {
  { name, parameters, body, attributes, span, }
}

///|
pub fn FunctionDefinition::name(self : FunctionDefinition) -> String {
  self.name
}

///|
pub fn FunctionDefinition::parameters(
  self : FunctionDefinition,
) -> ArrayView[FunctionParameter] {
  self.parameters[:]
}

///|
pub fn FunctionDefinition::body(self : FunctionDefinition) -> Expression {
  self.body
}

///|
pub fn FunctionDefinition::attributes(
  self : FunctionDefinition,
) -> ArrayView[Attribute] {
  self.attributes[:]
}

///|
pub fn FunctionDefinition::span(self : FunctionDefinition) -> @source.Span {
  self.span
}

///|
pub(all) struct Alias {
  name : String
  target : String
  attributes : Array[Attribute]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Alias::new(
  name : String,
  target : String,
  span : @source.Span,
  attributes? : Array[Attribute] = [],
) -> Alias {
  { name, target, attributes, span, }
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
pub fn Alias::attributes(self : Alias) -> ArrayView[Attribute] {
  self.attributes[:]
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
  { name, value, span, }
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
  { path, optional, span, }
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
  name_span : @source.Span
  path : StringLiteral?
  optional : Bool
  attributes : Array[Attribute]
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Module::new(
  name : String,
  name_span : @source.Span,
  path : StringLiteral?,
  optional : Bool,
  span : @source.Span,
  attributes? : Array[Attribute] = [],
) -> Module {
  { name, name_span, path, optional, attributes, span, }
}

///|
pub fn Module::name(self : Module) -> String {
  self.name
}

///|
pub fn Module::name_span(self : Module) -> @source.Span {
  self.name_span
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
pub fn Module::attributes(self : Module) -> ArrayView[Attribute] {
  self.attributes[:]
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
  trailing_comment : String?
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
  trailing_comment? : String,
) -> Recipe {
  {
    name,
    quiet,
    parameters,
    dependencies,
    subsequent_dependencies,
    lines,
    attributes,
    trailing_comment,
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
pub fn Recipe::trailing_comment(self : Recipe) -> String? {
  self.trailing_comment
}

///|
pub fn Recipe::span(self : Recipe) -> @source.Span {
  self.span
}

///|
pub(all) enum Item {
  Assignment(Assignment)
  Function(FunctionDefinition)
  Alias(Alias)
  Recipe(Recipe)
  Setting(Setting)
  Attribute(Attribute)
  Import(Import)
  Module(Module)
  Unexport(name~ : String, span~ : @source.Span)
  Comment(text~ : String, span~ : @source.Span)
  TrailingComment(text~ : String, span~ : @source.Span)
  Blank(span~ : @source.Span)
} derive(Eq, Debug)

///|
pub fn Item::span(self : Item) -> @source.Span {
  match self {
    Assignment(item) => item.span()
    Function(item) => item.span()
    Alias(item) => item.span()
    Recipe(item) => item.span()
    Setting(item) => item.span()
    Attribute(item) => item.span()
    Import(item) => item.span()
    Module(item) => item.span()
    Unexport(span~, ..) => span
    Comment(span~, ..) => span
    TrailingComment(span~, ..) => span
    Blank(span~) => span
  }
}

///|
pub fn Item::name(self : Item) -> String? {
  match self {
    Assignment(item) => Some(item.name())
    Function(item) => Some(item.name())
    Alias(item) => Some(item.name())
    Recipe(item) => Some(item.name())
    Setting(item) => Some(item.name())
    Attribute(item) => Some(item.name())
    Unexport(name~, ..) => Some(name)
    Import(_) | Module(_) | Comment(_) | TrailingComment(_) | Blank(_) => None
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
  { source_id, items, span, }
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
