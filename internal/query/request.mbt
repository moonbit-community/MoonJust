///|
priv struct RecipeFilter {
  groups : ReadOnlyArray[String]
  unsorted : Bool
}

///|
fn RecipeFilter::from_cli(arguments : @cli.CliArguments) -> RecipeFilter {
  {
    groups: ReadOnlyArray::from_array(arguments.values("group")),
    unsorted: arguments.flag("unsorted"),
  }
}

///|
priv struct ListOptions {
  filter : RecipeFilter
  heading : String
  prefix : String
  alias_style : String
  hide_aliases : Bool
  submodules : Bool
}

///|
fn ListOptions::from_cli(arguments : @cli.CliArguments) -> ListOptions {
  {
    filter: RecipeFilter::from_cli(arguments),
    heading: arguments.value("list-heading").unwrap(),
    prefix: arguments.value("list-prefix").unwrap(),
    alias_style: arguments.value("alias-style").unwrap(),
    hide_aliases: arguments.flag("no-aliases"),
    submodules: arguments.flag("list-submodules"),
  }
}

///|
pub(all) suberror QueryError {
  Query(String)
  Evaluation(@evaluator.EvaluationError)
  UnsupportedCommand(String)
}

///|
priv enum ListTarget {
  Arguments(ReadOnlyArray[String])
  Module(@modulepath.ModulePath)
}

///|
/// Prepared rendering inputs. Recipe paths for --usage are resolved before
/// application evaluates globals, preserving the order of user diagnostics.
enum QueryRequest {
  Summary(RecipeFilter, quiet~ : Bool)
  ListModule(ListTarget, ListOptions)
  Show(@modulepath.ModulePath, String)
  Usage(@modulepath.ModulePath, String, String)
  Variables
  Groups(RecipeFilter, prefix~ : String)
}

///|
pub fn build_query(
  project : @semantic.ProjectCompilation,
  arguments : @cli.CliArguments,
) -> QueryRequest raise QueryError {
  let path = arguments.positional()
  match arguments.command() {
    SummaryCommand =>
      Summary(RecipeFilter::from_cli(arguments), quiet=arguments.flag("quiet"))
    ListCommand =>
      ListModule(
        Arguments(ReadOnlyArray::from_array(path)),
        ListOptions::from_cli(arguments),
      )
    ShowCommand => {
      guard !path.is_empty() else { raise Query("`--show` requires recipe") }
      let (module_path, recipe, _) = query_recipe_path(project, path)
      Show(module_path, recipe)
    }
    UsageCommand => {
      guard !path.is_empty() else { raise Query("`--usage` requires recipe") }
      let (module_path, recipe, display) = query_recipe_path(project, path)
      Usage(module_path, recipe, display)
    }
    VariablesCommand => Variables
    GroupsCommand => {
      if path.get(0) is Some(argument) {
        raise Query(
          "`--groups` used with unexpected argument: `" + argument + "`",
        )
      }
      Groups(
        RecipeFilter::from_cli(arguments),
        prefix=arguments.value("list-prefix").unwrap(),
      )
    }
    command => raise UnsupportedCommand("\{Repr(command)}")
  }
}

///|
pub fn QueryRequest::needs_globals(self : QueryRequest) -> Bool {
  self is ListModule(_, _) || self is Usage(_, _, _)
}

///|
/// Default-list preflight has already resolved the module for this invocation.
pub fn QueryRequest::default_list(
  path : @modulepath.ModulePath,
  arguments : @cli.CliArguments,
) -> QueryRequest {
  ListModule(Module(path), ListOptions::from_cli(arguments))
}
