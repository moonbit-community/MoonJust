///|
fn justfile_indentation(ast : @syntax.Ast) -> String? raise ApplicationError {
  let mut result : String? = None
  for item in ast.items() {
    match item {
      Setting(value) if value.name() == "indentation" =>
        match value.value() {
          Some(String(literal)) => result = Some(literal.cooked())
          _ =>
            raise Format(
              InvalidInput(
                "`indentation` setting must be a plain string literal",
              ),
            )
        }
      _ => ()
    }
  }
  result
}

///|
fn formatting_indentation(
  arguments : @cli.CliArguments,
  ast : @syntax.Ast,
) -> String raise ApplicationError {
  match arguments.value("indentation") {
    Some(value) => value
    None => justfile_indentation(ast).unwrap_or("    ")
  }
}
