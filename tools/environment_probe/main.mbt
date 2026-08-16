///|
fn unix_path(value : String) -> @path.PathValue raise @path.PathError {
  @path.PathValue::new(value, Unix)
}

///|
fn linux() -> @environment.PlatformConfiguration {
  @environment.PlatformConfiguration::new(
    @host.PlatformInfo::new(Linux, "x86_64", Unix),
  )
}

///|
fn shell_arguments(arguments : ArrayView[String]) -> Array[String] raise {
  let parsed = @cli.parse_arguments(arguments, {})
  let shell = @environment.resolve_shell(
    linux(),
    cli_shell=parsed.value("shell"),
    cli_arguments=parsed.shell_arguments(),
  )
  shell.arguments().to_owned()
}

///|
fn precedence() -> String {
  let ambient = @environment.EnvTable::from_entries(
    [("AMBIENT", "ambient"), ("ORDER", "ambient"), ("REMOVED", "ambient")][:],
  )
  let dotenv = @environment.EnvTable::from_entries(
    [("DOTENV", "dotenv"), ("ORDER", "dotenv")][:],
  )
  let exported = @environment.EnvTable::from_entries(
    [("EXPORTED", "exported"), ("ORDER", "exported")][:],
  )
  let parameters = @environment.EnvTable::from_entries(
    [("PARAM", "argument")][:],
  )
  let recipe = @environment.EnvTable::from_entries(
    [("RECIPE", "recipe"), ("ORDER", "recipe")][:],
  )
  let result = @environment.compose_process_environment(
    ambient,
    dotenv,
    exported,
    parameters,
    recipe,
    unexports=["REMOVED"],
  )
  ["AMBIENT", "DOTENV", "EXPORTED", "PARAM", "RECIPE", "ORDER", "REMOVED"]
  .map(fn(name) { result.get(name).unwrap_or("unset") })
  .join("|")
}

///|
fn run(arguments : ArrayView[String]) -> String raise {
  guard arguments.get(0) is Some(case) else { abort("expected probe case") }
  match case {
    "set" => {
      let parsed = @cli.parse_arguments(
        ["--set", "value", "first", "--set", "value", "overridden"],
        {},
      )
      @environment.OverrideTable::from_entries(parsed.variable_overrides())
      .get("value")
      .unwrap()
      .value()
    }
    "shell-two" =>
      shell_arguments([
        "--shell", "probe", "--shell-arg", "one", "--shell-arg", "two",
      ]).join("\n")
    "shell-clear" =>
      shell_arguments([
        "--shell", "probe", "--shell-arg", "ignored", "--clear-shell-args",
      ]).join("\n")
    "shell-reset" =>
      shell_arguments([
        "--shell", "probe", "--clear-shell-args", "--shell-arg", "last",
      ]).join("\n")
    "tempdir" => {
      guard arguments.get(1) is Some(project) else {
        abort("expected project directory")
      }
      @environment.resolve_temporary_directory(
        unix_path(project),
        cli_tempdir=Some("custom-temp"),
      )
      .directory()
      .unwrap()
      .as_string()
    }
    "precedence" => precedence()
    _ => abort("unknown probe case")
  }
}

///|
fn main {
  let arguments = @env.args()
  let output = try! run(arguments[1:])
  if !output.is_empty() {
    println(output)
  }
}
