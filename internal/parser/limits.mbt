///|
/// Resource limits applied independently of the lexer budgets.
pub struct ParserLimits {
  max_depth : Int32
  max_nodes : Int32
  max_diagnostics : Int32
} derive(Eq, Debug)

///|
fn default_parser_depth() -> Int32 {
  if @env.get_env_var("MOONJUST_OS") == Some("windows") ||
    @env.get_env_var("OS") == Some("Windows_NT") {
    48
  } else {
    256
  }
}

///|
pub fn ParserLimits::new(
  max_depth : Int32,
  max_nodes : Int32,
  max_diagnostics : Int32,
) -> ParserLimits raise ParserConfigurationError {
  if max_depth <= 0 || max_nodes <= 0 || max_diagnostics <= 0 {
    raise InvalidParserLimit
  }
  { max_depth, max_nodes, max_diagnostics, }
}

///|
pub fn ParserLimits::default() -> ParserLimits {
  {
    max_depth: default_parser_depth(),
    max_nodes: 1_000_000,
    max_diagnostics: 64,
  }
}

///|
pub fn ParserLimits::max_depth(self : ParserLimits) -> Int32 {
  self.max_depth
}

///|
pub fn ParserLimits::max_nodes(self : ParserLimits) -> Int32 {
  self.max_nodes
}

///|
pub fn ParserLimits::max_diagnostics(self : ParserLimits) -> Int32 {
  self.max_diagnostics
}

///|
pub(all) suberror ParserConfigurationError {
  InvalidParserLimit
} derive(Eq, Debug)
