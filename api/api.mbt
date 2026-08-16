///|
/// Parse a source buffer using the stable MoonJust facade.
pub fn parse(source : @source.Source) -> @syntax.Ast raise @parser.ParserError {
  @parser.parse(source)
}

///|
/// Format a source buffer canonically.
pub fn format_source(
  source : @source.Source,
) -> String raise @formatter.FormatterError {
  @formatter.format_source(source)
}

///|
/// Compile a parsed source into the immutable semantic model.
pub fn compile_source(
  source : @source.Source,
) -> @semantic.Compilation raise @semantic.SemanticError {
  @semantic.compile_source(source)
}

///|
/// Evaluate one pure expression with explicit scope and limits.
pub fn evaluate_expression(
  expression : @syntax.Expression,
  environment? : @evaluator.Environment = @evaluator.Environment::new(),
  limits? : @evaluator.EvaluationLimits = @evaluator.EvaluationLimits::default(),
) -> @value.Value raise @evaluator.EvaluationError {
  @evaluator.evaluate(expression, environment~, limits~)
}
