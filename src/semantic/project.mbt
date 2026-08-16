///|
pub(all) suberror ProjectCompilationError {
  MissingRootModule
  DuplicateModulePath(String)
} derive(Eq, Debug)

///|
pub struct ProjectModule {
  module_path : @modulepath.ModulePath
  compilation : Compilation
  directory : @path.PathValue
  source_file : @path.PathValue?
  source_files : Array[(@source.SourceId, @path.PathValue)]
  declaration_attributes : Array[@syntax.Attribute]
  declaration_doc : String?
  default_recipe : String?
} derive(Debug)

///|
pub fn ProjectModule::new(
  module_path : @modulepath.ModulePath,
  compilation : Compilation,
  directory : @path.PathValue,
  source_file? : @path.PathValue,
  source_files? : ArrayView[(@source.SourceId, @path.PathValue)] = [],
  declaration_attributes? : Array[@syntax.Attribute] = [],
  declaration_doc? : String,
  default_recipe? : String,
) -> ProjectModule {
  {
    module_path,
    compilation,
    directory,
    source_file,
    source_files: source_files.to_owned(),
    declaration_attributes,
    declaration_doc,
    default_recipe,
  }
}

///|
pub fn ProjectModule::module_path(
  self : ProjectModule,
) -> @modulepath.ModulePath {
  self.module_path
}

///|
pub fn ProjectModule::compilation(self : ProjectModule) -> Compilation {
  self.compilation
}

///|
pub fn ProjectModule::directory(self : ProjectModule) -> @path.PathValue {
  self.directory
}

///|
pub fn ProjectModule::source_file(self : ProjectModule) -> @path.PathValue? {
  self.source_file
}

///|
pub fn ProjectModule::source_files(
  self : ProjectModule,
) -> ArrayView[(@source.SourceId, @path.PathValue)] {
  self.source_files[:]
}

///|
pub fn ProjectModule::declaration_attributes(
  self : ProjectModule,
) -> ArrayView[@syntax.Attribute] {
  self.declaration_attributes[:]
}

///|
pub fn ProjectModule::declaration_doc(self : ProjectModule) -> String? {
  self.declaration_doc
}

///|
pub fn ProjectModule::default_recipe(self : ProjectModule) -> String? {
  self.default_recipe
}

///|
/// Compilation model for a root module and its independently scoped submodules.
/// Entries retain deterministic discovery order for list/dump operations.
pub struct ProjectCompilation {
  module_order : Array[@modulepath.ModulePath]
  modules : Map[@modulepath.ModulePath, ProjectModule]
  absent_modules : Set[@modulepath.ModulePath]
  disabled_recipes : Set[String]
  disabled_aliases : Set[String]
  disabled_reasons : Map[String, Array[@modulepath.ModulePath]]
} derive(Debug)

///|
/// A recipe resolved in its owning module.
pub struct ProjectRecipe {
  module_path : @modulepath.ModulePath
  recipe_name : String
} derive(Eq, Debug)

///|
pub fn ProjectRecipe::module_path(
  self : ProjectRecipe,
) -> @modulepath.ModulePath {
  self.module_path
}

///|
pub fn ProjectRecipe::recipe_name(self : ProjectRecipe) -> String {
  self.recipe_name
}

///|
pub fn ProjectCompilation::new(
  entries : Array[ProjectModule],
  absent_modules? : ArrayView[@modulepath.ModulePath] = [],
) -> ProjectCompilation raise ProjectCompilationError {
  let module_order : Array[@modulepath.ModulePath] = []
  let modules : Map[@modulepath.ModulePath, ProjectModule] = Map([])
  let absent : Set[@modulepath.ModulePath] = Set([])
  for path in absent_modules {
    absent.add(path)
  }
  for entry in entries {
    let path = entry.module_path()
    if modules.contains(path) {
      raise DuplicateModulePath(path.as_string())
    }
    module_order.push(path)
    modules[path] = entry
  }
  if !modules.contains(@modulepath.ModulePath::root()) {
    raise MissingRootModule
  }
  {
    module_order,
    modules,
    absent_modules: absent,
    disabled_recipes: Set([]),
    disabled_aliases: Set([]),
    disabled_reasons: Map([]),
  }
}

///|
pub fn ProjectCompilation::from_root(
  compilation : Compilation,
  directory : @path.PathValue,
) -> ProjectCompilation {
  try! ProjectCompilation::new([
    ProjectModule::new(@modulepath.ModulePath::root(), compilation, directory),
  ])
}

///|
pub fn ProjectCompilation::root(self : ProjectCompilation) -> Compilation {
  self.modules[@modulepath.ModulePath::root()].compilation()
}

///|
pub fn ProjectCompilation::module_compilation(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
) -> Compilation? {
  self.modules.get(path).map(ProjectModule::compilation)
}

///|
pub fn ProjectCompilation::directory(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
) -> @path.PathValue? {
  self.modules.get(path).map(ProjectModule::directory)
}

///|
pub fn ProjectCompilation::source_file(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
) -> @path.PathValue? {
  match self.modules.get(path) {
    Some(project_module) => project_module.source_file()
    None => None
  }
}

///|
pub fn ProjectCompilation::source_files(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
) -> ArrayView[(@source.SourceId, @path.PathValue)] {
  match self.modules.get(path) {
    Some(project_module) => project_module.source_files()
    None => []
  }
}

///|
pub fn ProjectCompilation::module_declaration_attributes(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
) -> ArrayView[@syntax.Attribute] {
  match self.modules.get(path) {
    Some(project_module) => project_module.declaration_attributes()
    None => []
  }
}

///|
pub fn ProjectCompilation::module_declaration_doc(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
) -> String? {
  match self.modules.get(path) {
    Some(project_module) => project_module.declaration_doc()
    None => None
  }
}

///|
pub fn ProjectCompilation::default_recipe(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
) -> String? {
  match self.modules.get(path) {
    Some(project_module) =>
      match project_module.default_recipe() {
        Some(name) => Some(name)
        None if project_module.source_file() is None => {
          let compilation = project_module.compilation()
          for name in compilation.recipe_names() {
            match compilation.recipe_attributes(name) {
              Some(attributes) if attributes.names().contains("default") =>
                return Some(name)
              _ => ()
            }
          }
          compilation.recipe_names().get(0).map(fn(name) { name })
        }
        None => None
      }
    None => None
  }
}

///|
pub fn ProjectCompilation::module_paths(
  self : ProjectCompilation,
) -> ArrayView[@modulepath.ModulePath] {
  self.module_order[:]
}

///|
pub fn ProjectCompilation::modules(
  self : ProjectCompilation,
) -> Array[ProjectModule] {
  self.module_order.map(fn(path) { self.modules[path] })
}

///|
pub fn ProjectCompilation::is_absent_module(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
) -> Bool {
  self.absent_modules.contains(path)
}

///|
fn project_symbol_key(path : @modulepath.ModulePath, name : String) -> String {
  path.as_string() + "\u{0000}" + name
}

///|
pub fn ProjectCompilation::recipe_disabled(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
  name : String,
) -> Bool {
  self.disabled_recipes.contains(project_symbol_key(path, name))
}

///|
pub fn ProjectCompilation::alias_disabled(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
  name : String,
) -> Bool {
  self.disabled_aliases.contains(project_symbol_key(path, name))
}

///|
fn ProjectCompilation::add_disabled_reason(
  self : ProjectCompilation,
  key : String,
  path : @modulepath.ModulePath,
) -> Unit {
  let reasons = self.disabled_reasons.get(key).unwrap_or([])
  if !reasons.contains(path) {
    reasons.push(path)
  }
  self.disabled_reasons[key] = reasons
}

///|
fn ProjectCompilation::copy_disabled_reasons(
  self : ProjectCompilation,
  from : String,
  to : String,
) -> Unit {
  for path in self.disabled_reasons.get(from).unwrap_or([]) {
    self.add_disabled_reason(to, path)
  }
}

///|
pub fn ProjectCompilation::recipe_absent_modules(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
  name : String,
) -> ArrayView[@modulepath.ModulePath] {
  self.disabled_reasons.get(project_symbol_key(path, name)).unwrap_or([])[:]
}

///|
pub fn ProjectCompilation::alias_absent_modules(
  self : ProjectCompilation,
  path : @modulepath.ModulePath,
  name : String,
) -> ArrayView[@modulepath.ModulePath] {
  self.disabled_reasons.get(project_symbol_key(path, name)).unwrap_or([])[:]
}

///|
fn ProjectCompilation::absent_module_reference(
  self : ProjectCompilation,
  from : @modulepath.ModulePath,
  requested : String,
  seen : Set[String],
) -> @modulepath.ModulePath? {
  let seen_key = from.as_string() + "\u{0000}" + requested
  if seen.contains(seen_key) {
    return None
  }
  seen.add(seen_key)
  guard self.module_compilation(from) is Some(compilation) else { return None }
  match compilation.alias_target(requested) {
    Some(target) =>
      match self.absent_module_reference(from, target, seen) {
        Some(path) => return Some(path)
        None => ()
      }
    None => ()
  }
  let parsed = try @modulepath.ModulePath::parse(requested) catch {
    _ => return None
  } noraise {
    value => value
  }
  let mut current = from
  for component in parsed.components() {
    let candidate = current.child(component) catch { _ => return None }
    if self.absent_modules.contains(candidate) {
      return Some(candidate)
    }
    if self.module_compilation(candidate) is None {
      return None
    }
    current = candidate
  }
  None
}

///|
pub fn ProjectCompilation::absent_module_for_reference(
  self : ProjectCompilation,
  from : @modulepath.ModulePath,
  requested : String,
) -> @modulepath.ModulePath? {
  self.absent_module_reference(from, requested, Set([]))
}

///|
fn ProjectCompilation::resolve_module_reference(
  self : ProjectCompilation,
  from : @modulepath.ModulePath,
  requested : String,
  seen : Set[String],
) -> @modulepath.ModulePath? {
  let seen_key = from.as_string() + "\u{0000}" + requested
  if seen.contains(seen_key) {
    return None
  }
  seen.add(seen_key)
  guard self.module_compilation(from) is Some(compilation) else { return None }
  match compilation.alias_target(requested) {
    Some(target) =>
      match self.resolve_module_reference(from, target, seen) {
        Some(path) => return Some(path)
        None => ()
      }
    None => ()
  }
  let parsed = try @modulepath.ModulePath::parse(requested) catch {
    _ => return None
  } noraise {
    value => value
  }
  let mut current = from
  for component in parsed.components() {
    let current_compilation = self.module_compilation(current).unwrap()
    match current_compilation.alias_target(component) {
      Some(target) =>
        match self.resolve_module_reference(current, target, seen) {
          Some(path) => {
            current = path
            continue
          }
          None => ()
        }
      None => ()
    }
    let candidate = current.child(component) catch { _ => return None }
    if self.module_compilation(candidate) is None {
      return None
    }
    current = candidate
  }
  Some(current)
}

///|
/// Resolve a module path or a module alias relative to `from`.
pub fn ProjectCompilation::resolve_module(
  self : ProjectCompilation,
  from : @modulepath.ModulePath,
  requested : String,
) -> @modulepath.ModulePath? {
  self.resolve_module_reference(from, requested, Set([]))
}

///|
fn ProjectCompilation::resolve_recipe_reference(
  self : ProjectCompilation,
  from : @modulepath.ModulePath,
  requested : String,
  seen : Set[String],
) -> ProjectRecipe? {
  let seen_key = from.as_string() + "\u{0000}" + requested
  if seen.contains(seen_key) {
    return None
  }
  seen.add(seen_key)
  guard self.module_compilation(from) is Some(compilation) else { return None }
  match compilation.alias_target(requested) {
    Some(target) => return self.resolve_recipe_reference(from, target, seen)
    None => ()
  }
  let parsed = try @modulepath.ModulePath::parse(requested) catch {
    _ => return None
  } noraise {
    value => value
  }
  let components = parsed.components()
  if components.is_empty() {
    return None
  }
  let mut current = from
  for index, component in components {
    let current_compilation = self.module_compilation(current).unwrap()
    if index + 1 == components.length() {
      match current_compilation.alias_target(component) {
        Some(target) =>
          return self.resolve_recipe_reference(current, target, seen)
        None => ()
      }
      match current_compilation.recipe(component) {
        Some(_) => return Some({ module_path: current, recipe_name: component })
        None => ()
      }
    }
    match self.resolve_module_reference(current, component, seen) {
      Some(path) => current = path
      None => return None
    }
  }
  None
}

///|
/// Resolve a local recipe, recipe alias, module default, or qualified recipe.
pub fn ProjectCompilation::resolve_recipe(
  self : ProjectCompilation,
  from : @modulepath.ModulePath,
  requested : String,
) -> ProjectRecipe? {
  self.resolve_recipe_reference(from, requested, Set([]))
}

///|
fn project_recipe_key(recipe : ProjectRecipe) -> String {
  project_symbol_key(recipe.module_path(), recipe.recipe_name())
}

///|
fn project_recipe_display(recipe : ProjectRecipe) -> String {
  if recipe.module_path().is_root() {
    recipe.recipe_name()
  } else {
    recipe.module_path().as_string() + "::" + recipe.recipe_name()
  }
}

///|
fn validate_project_recipe(
  project : ProjectCompilation,
  address : ProjectRecipe,
  states : Map[String, Int],
  stack : Array[ProjectRecipe],
) -> Unit raise SemanticError {
  let key = project_recipe_key(address)
  match states.get(key) {
    Some(2) => return
    Some(1) => {
      let compilation = project
        .module_compilation(address.module_path())
        .unwrap()
      let recipe = compilation.recipe(address.recipe_name()).unwrap()
      raise DependencyCycle(
        name=project_recipe_display(address),
        span=recipe.span(),
      )
    }
    _ => ()
  }
  states[key] = 1
  stack.push(address)
  defer ignore(stack.pop())
  let compilation = project.module_compilation(address.module_path()).unwrap()
  let recipe = compilation.recipe(address.recipe_name()).unwrap()
  for dependency in recipe_dependencies(recipe) {
    guard project.resolve_recipe(address.module_path(), dependency.name())
      is Some(target) else {
      if project.absent_module_for_reference(
          address.module_path(),
          dependency.name(),
        )
        is Some(absent) {
        let address_key = project_recipe_key(address)
        project.disabled_recipes.add(address_key)
        project.add_disabled_reason(address_key, absent)
        continue
      }
      raise UndefinedRecipe(name=dependency.name(), span=dependency.span())
    }
    let target_key = project_recipe_key(target)
    if states.get(target_key) == Some(1) {
      let chain : Array[String] = []
      let mut in_cycle = false
      for item in stack {
        if project_recipe_key(item) == target_key {
          in_cycle = true
        }
        if in_cycle {
          chain.push(project_recipe_display(item))
        }
      }
      chain.push(project_recipe_display(target))
      raise RecipeDependencyCycle(
        recipe=project_recipe_display(address),
        chain~,
        span=dependency.span(),
      )
    }
    validate_project_recipe(project, target, states, stack)
    if project.recipe_disabled(target.module_path(), target.recipe_name()) {
      let address_key = project_recipe_key(address)
      project.disabled_recipes.add(address_key)
      project.copy_disabled_reasons(project_recipe_key(target), address_key)
      continue
    }
    let target_compilation = project
      .module_compilation(target.module_path())
      .unwrap()
    let target_recipe = target_compilation.recipe(target.recipe_name()).unwrap()
    let parameters = target_recipe.parameters()
    let flag_parameters = recipe_flag_parameter_names(target_recipe)
    let mut required = 0
    let mut maximum = 0
    for parameter in parameters {
      if flag_parameters.contains(parameter.name()) {
        continue
      }
      maximum += 1
      if parameter.variadic() {
        required += parameter.variadic_minimum()
      } else if parameter.default_value() is None {
        required += 1
      }
    }
    let actual = dependency.arguments().length()
    let has_variadic = parameters.any(fn(parameter) { parameter.variadic() })
    let lists = target_compilation.settings().bool("lists")
    if actual < required || (actual > maximum && (!has_variadic || lists)) {
      raise InvalidDependencyArguments(
        name=dependency.name(),
        expected=if actual > maximum {
          "at most " + maximum.to_string()
        } else if has_variadic {
          "at least " + required.to_string()
        } else {
          required.to_string() + ".." + maximum.to_string()
        },
        actual~,
        span=dependency.span(),
      )
    }
  }
  states[key] = 2
}

///|
/// Link aliases and dependencies after every module has been compiled.
pub fn validate_project_compilation(
  project : ProjectCompilation,
) -> Unit raise SemanticError {
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    for symbol in compilation.symbols() {
      guard symbol.kind() == Alias else { continue }
      guard compilation.alias_target(symbol.name()) is Some(target) else {
        continue
      }
      if project.resolve_module(path, target) is None &&
        project.resolve_recipe(path, target) is None {
        if project.absent_module_for_reference(path, target) is Some(absent) {
          let alias_key = project_symbol_key(path, symbol.name())
          project.disabled_aliases.add(alias_key)
          project.add_disabled_reason(alias_key, absent)
        } else {
          raise UndefinedRecipe(name=target, span=symbol.span())
        }
      }
    }
  }
  let states : Map[String, Int] = Map([])
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    for recipe_name in compilation.recipe_names() {
      validate_project_recipe(
        project,
        { module_path: path, recipe_name },
        states,
        [],
      )
    }
  }
  for path in project.module_paths() {
    let compilation = project.module_compilation(path).unwrap()
    for symbol in compilation.symbols() {
      guard symbol.kind() == Alias else { continue }
      match project.resolve_recipe(path, symbol.name()) {
        Some(recipe) if project.recipe_disabled(
            recipe.module_path(),
            recipe.recipe_name(),
          ) => {
          let alias_key = project_symbol_key(path, symbol.name())
          project.disabled_aliases.add(alias_key)
          project.copy_disabled_reasons(project_recipe_key(recipe), alias_key)
        }
        _ => ()
      }
    }
  }
}
