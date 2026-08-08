///|
fn path(value : String) -> @path.PathValue raise @path.PathError {
  @path.PathValue::new(value, Unix)
}

///|
fn child(
  parent : @path.PathValue,
  value : String,
) -> @path.PathValue raise @path.PathError {
  parent.join(path(value))
}

///|
fn run(root : @path.PathValue, case : String) -> @path.PathValue raise {
  let invocation = child(root, "inv")
  let justfile = child(root, "justfile")
  let model = @workdir.WorkingDirectoryModel::from_justfile(
    invocation, justfile,
  )
  match case {
    "project" => model.recipe_directory()
    "no-cd" => model.recipe_directory(recipe_no_cd=true)
    "setting" => model.recipe_directory(module_setting=Some("build"))
    "setting-attribute" =>
      model.recipe_directory(
        module_setting=Some("build"),
        recipe_working_directory=Some("release"),
      )
    "attribute-over-no-cd" =>
      model.recipe_directory(
        module_no_cd=true,
        recipe_working_directory=Some("release"),
      )
    "import" =>
      model.for_import(child(root, "includes/tasks.just")).recipe_directory()
    "module" =>
      model
      .for_module(child(root, "modules/release/mod.just"))
      .recipe_directory()
    "symlink" => {
      let link_directory = child(root, "link")
      @workdir.WorkingDirectoryModel::from_justfile(
        child(link_directory, "sub"),
        path("../justfile"),
      ).recipe_directory()
    }
    "cli-override" =>
      @workdir.WorkingDirectoryModel::from_justfile(
        invocation,
        child(root, "config/justfile"),
        working_directory=Some(child(root, "run")),
      ).recipe_directory()
    _ => abort("unknown working-directory probe case")
  }
}

///|
fn main {
  let arguments = @env.args()
  guard arguments.length() == 3 else { abort("expected fixture root and case") }
  println((try! run(path(arguments[1]), arguments[2])).as_string())
}
