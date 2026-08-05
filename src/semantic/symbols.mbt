///|
/// The kind of a named definition in a compiled justfile.
pub(all) enum SymbolKind {
  Variable
  Recipe
  Alias
} derive(Eq, Debug)

///|
pub(all) struct Symbol {
  name : String
  kind : SymbolKind
  span : @source.Span
} derive(Eq, Debug)

///|
pub fn Symbol::new(
  name : String,
  kind : SymbolKind,
  span : @source.Span,
) -> Symbol {
  { name, kind, span }
}

///|
pub fn Symbol::name(self : Symbol) -> String {
  self.name
}

///|
pub fn Symbol::kind(self : Symbol) -> SymbolKind {
  self.kind
}

///|
pub fn Symbol::span(self : Symbol) -> @source.Span {
  self.span
}
