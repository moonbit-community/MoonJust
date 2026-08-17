///|
/// Resource limits applied independently of the lexer budgets.
pub struct ParserLimits {
  max_depth : Int
  max_nodes : Int
  max_diagnostics : Int
} derive(Eq, Debug)

///|
pub fn ParserLimits::new(
  max_depth : Int,
  max_nodes : Int,
  max_diagnostics : Int,
) -> ParserLimits raise ParserConfigurationError {
  if max_depth <= 0 || max_nodes <= 0 || max_diagnostics <= 0 {
    raise InvalidParserLimit
  }
  { max_depth, max_nodes, max_diagnostics }
}

///|
pub fn ParserLimits::default() -> ParserLimits {
  { max_depth: 256, max_nodes: 1_000_000, max_diagnostics: 64 }
}

///|
pub fn ParserLimits::max_depth(self : ParserLimits) -> Int {
  self.max_depth
}

///|
pub fn ParserLimits::max_nodes(self : ParserLimits) -> Int {
  self.max_nodes
}

///|
pub fn ParserLimits::max_diagnostics(self : ParserLimits) -> Int {
  self.max_diagnostics
}

///|
pub(all) suberror ParserConfigurationError {
  InvalidParserLimit
} derive(Eq, Debug)
