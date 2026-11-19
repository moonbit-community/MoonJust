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
/// Resolve usage paths once and retain the user's spelling for display.
enum QueryRequest {
  Summary(RecipeFilter, quiet~ : Bool)
  ListModule(ListTarget, ListOptions)
  Show(@modulepath.ModulePath, String)
  Usage(@modulepath.ModulePath, String, String)
  ModuleUsage(@modulepath.ModulePath, String, unsorted~ : Bool, quiet~ : Bool)
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
    ShowCommand | UsageCommand => {
      let (requested, display) = query_path(path)
      let parts = requested.components()
      let root = @modulepath.ModulePath::root()
      if arguments.command() == UsageCommand {
        let module_path = if parts.is_empty() {
          Some(root)
        } else {
          project.resolve_module(root, requested.as_string())
        }
        if module_path is Some(module_path) {
          return ModuleUsage(
            module_path,
            parts.join(" "),
            unsorted=arguments.flag("unsorted"),
            quiet=arguments.flag("quiet"),
          )
        }
      }
      guard parts.last() is Some(recipe) else {
        raise Query("`--show` requires recipe")
      }
      let mut module_path = root
      for component in parts[:parts.length() - 1] {
        match project.resolve_module(module_path, component) {
          Some(child) => module_path = child
          None => {
            if project.absent_module_for_reference(module_path, component)
              is Some(absent) {
              raise Query(
                "optional module `" + absent.as_string() + "` is absent",
              )
            }
            raise Query(
              unknown_submodule_message(
                project,
                module_path,
                component,
                display~,
              ),
            )
          }
        }
      }
      let alias_disabled = project.alias_disabled(module_path, recipe)
      if alias_disabled || project.recipe_disabled(module_path, recipe) {
        let (kind, modules) = if alias_disabled {
          ("alias", project.alias_absent_modules(module_path, recipe))
        } else {
          ("recipe", project.recipe_absent_modules(module_path, recipe))
        }
        raise Query(
          kind +
          " `" +
          display +
          "` depends on absent module" +
          (if modules.length() == 1 { " `" } else { "s `" }) +
          modules.map(fn(value) { value.as_string() }).join("` and `") +
          "`",
        )
      }
      if project.absent_module_for_reference(module_path, recipe)
        is Some(absent) {
        raise Query("optional module `" + absent.as_string() + "` is absent")
      }
      if arguments.command() == ShowCommand {
        Show(module_path, recipe)
      } else {
        Usage(module_path, recipe, display)
      }
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
/// Default-list preflight has already resolved the module for this invocation.
pub fn QueryRequest::default_list(
  path : @modulepath.ModulePath,
  arguments : @cli.CliArguments,
) -> QueryRequest {
  ListModule(Module(path), ListOptions::from_cli(arguments))
}
