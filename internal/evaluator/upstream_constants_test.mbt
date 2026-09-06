///|
test "upstream constants::constants_are_defined" {
  let environment = Environment::new()
  install_constants(environment, Unix)
  let source = @source.Source::from_text(
    @source.SourceId::new(709),
    "expr",
    "HEX",
  )
  assert_eq(
    try! evaluate_source(source, environment~).to_string(),
    "0123456789abcdef",
  )
}

///|
test "upstream constants::constants_can_have_different_values_on_windows" {
  let unix = Environment::new()
  install_constants(unix, Unix)
  let windows = Environment::new()
  install_constants(windows, Windows)
  let unix_sep = @source.Source::from_text(
    @source.SourceId::new(710),
    "expr",
    "PATH_SEP",
  )
  let windows_sep = @source.Source::from_text(
    @source.SourceId::new(711),
    "expr",
    "PATH_SEP",
  )
  let unix_var = @source.Source::from_text(
    @source.SourceId::new(712),
    "expr",
    "PATH_VAR_SEP",
  )
  let windows_var = @source.Source::from_text(
    @source.SourceId::new(713),
    "expr",
    "PATH_VAR_SEP",
  )
  assert_eq(try! evaluate_source(unix_sep, environment=unix).to_string(), "/")
  assert_eq(
    try! evaluate_source(windows_sep, environment=windows).to_string(),
    "\\",
  )
  assert_eq(try! evaluate_source(unix_var, environment=unix).to_string(), ":")
  assert_eq(
    try! evaluate_source(windows_var, environment=windows).to_string(),
    ";",
  )
}
