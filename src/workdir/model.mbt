///|
fn resolve_from(
  base : @path.PathValue,
  value : @path.PathValue,
) -> @path.PathValue raise WorkingDirectoryError {
  base.join(value) catch {
    error => raise Path(error)
  }
}

///|
fn child_path(
  base : @path.PathValue,
  value : String,
) -> @path.PathValue raise WorkingDirectoryError {
  let child = @path.PathValue::new(value, base.flavor()) catch {
    error => raise Path(error)
  }
  resolve_from(base, child)
}

///|
/// All directories that influence evaluation and eventual recipe execution.
/// Paths remain lexical so a justfile reached through a symlink keeps the
/// directory through which the user reached it.
pub struct WorkingDirectoryModel {
  invocation : @path.PathValue
  project : @path.PathValue
  module_base : @path.PathValue
  justfile : @path.PathValue?
} derive(Eq, Debug)

///|
/// Resolve an explicit justfile and optional CLI working directory relative to
/// the invocation directory.
pub fn WorkingDirectoryModel::from_justfile(
  invocation : @path.PathValue,
  justfile : @path.PathValue,
  working_directory? : @path.PathValue? = None,
) -> WorkingDirectoryModel raise WorkingDirectoryError {
  let resolved_justfile = resolve_from(invocation, justfile)
  let justfile_parent = match resolved_justfile.parent() {
    Some(directory) => directory
    None => raise JustfileWithoutParent(resolved_justfile)
  }
  let project = match working_directory {
    Some(directory) => resolve_from(invocation, directory)
    None => justfile_parent
  }
  {
    invocation,
    project,
    module_base: project,
    justfile: Some(resolved_justfile),
  }
}

///|
/// Build a model for stdin, whose project directory is the invocation directory
/// unless the CLI supplied `--working-directory`.
pub fn WorkingDirectoryModel::from_stdin(
  invocation : @path.PathValue,
  working_directory? : @path.PathValue? = None,
) -> WorkingDirectoryModel raise WorkingDirectoryError {
  let project = match working_directory {
    Some(directory) => resolve_from(invocation, directory)
    None => invocation
  }
  { invocation, project, module_base: project, justfile: None, }
}

///|
/// A global justfile is loaded from user configuration, but its root recipes
/// execute in the invocation project instead of the configuration directory.
pub fn WorkingDirectoryModel::from_global_justfile(
  invocation : @path.PathValue,
  justfile : @path.PathValue,
  project : @path.PathValue,
) -> WorkingDirectoryModel raise WorkingDirectoryError {
  let resolved_justfile = resolve_from(invocation, justfile)
  let resolved_project = resolve_from(invocation, project)
  {
    invocation,
    project: resolved_project,
    module_base: resolved_project,
    justfile: Some(resolved_justfile),
  }
}

///|
pub fn WorkingDirectoryModel::invocation_directory(
  self : WorkingDirectoryModel,
) -> @path.PathValue {
  self.invocation
}

///|
pub fn WorkingDirectoryModel::project_directory(
  self : WorkingDirectoryModel,
) -> @path.PathValue {
  self.project
}

///|
pub fn WorkingDirectoryModel::module_directory(
  self : WorkingDirectoryModel,
) -> @path.PathValue {
  self.module_base
}

///|
pub fn WorkingDirectoryModel::justfile(
  self : WorkingDirectoryModel,
) -> @path.PathValue? {
  self.justfile
}

///|
/// Imports remain in the containing module, regardless of the imported file's
/// own directory.
pub fn WorkingDirectoryModel::for_import(
  self : WorkingDirectoryModel,
  _source_file : @path.PathValue,
) -> WorkingDirectoryModel {
  self
}

///|
/// Modules establish a new cwd at the directory containing their source file.
pub fn WorkingDirectoryModel::for_module(
  self : WorkingDirectoryModel,
  source_file : @path.PathValue,
) -> WorkingDirectoryModel raise WorkingDirectoryError {
  let resolved = resolve_from(self.module_base, source_file)
  let module_base = match resolved.parent() {
    Some(directory) => directory
    None => raise JustfileWithoutParent(resolved)
  }
  {
    invocation: self.invocation,
    project: self.project,
    module_base,
    justfile: self.justfile,
  }
}

///|
/// Directory used while evaluating module variables, backticks, shell calls,
/// and recipe working-directory attributes. `no-cd` does not affect evaluation.
pub fn WorkingDirectoryModel::evaluation_directory(
  self : WorkingDirectoryModel,
  module_setting? : String? = None,
) -> @path.PathValue raise WorkingDirectoryError {
  match module_setting {
    Some(directory) => child_path(self.module_base, directory)
    None => self.module_base
  }
}

///|
/// Resolve the cwd for one recipe. A recipe working-directory attribute wins
/// over module-level no-cd, and a recipe no-cd attribute wins over module cwd.
pub fn WorkingDirectoryModel::recipe_directory(
  self : WorkingDirectoryModel,
  module_setting? : String? = None,
  module_no_cd? : Bool = false,
  recipe_no_cd? : Bool = false,
  recipe_working_directory? : String? = None,
) -> @path.PathValue raise WorkingDirectoryError {
  let evaluation = self.evaluation_directory(module_setting~)
  match recipe_working_directory {
    Some(directory) => child_path(evaluation, directory)
    None if recipe_no_cd || module_no_cd => self.invocation
    None => evaluation
  }
}
