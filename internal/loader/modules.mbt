///|
/// Keep the names returned by the filesystem. An existence lookup alone can
/// match a differently cased name on case-insensitive filesystems.
async fn[T : @host.HostFs] module_directory_entries(
  host : T,
  directory : @path.PathValue,
  cache : Map[@path.PathValue, Set[String]],
) -> Set[String] raise LoaderError {
  if cache.get(directory) is Some(entries) {
    return entries
  }
  let entries = @host.HostFs::read_dir(host, directory) catch {
    NotFound(_) => []
    error => {
      // A regular file with the module directory's name contributes no entries.
      let metadata = @host.HostFs::metadata(host, directory) catch {
        _ => raise Host(error)
      }
      if metadata.is_directory() {
        raise Host(error)
      }
      []
    }
  }
  let names = Set::from_iter(entries.iter())
  cache[directory] = names
  names
}

///|
async fn[T : @host.HostFs] resolve_module_file(
  host : T,
  source_path : @path.PathValue,
  definition : @syntax.Module,
  source? : @source.Source,
  environment~ : ArrayView[(String, String)] = [],
  directory_cache~ : Map[@path.PathValue, Set[String]] = Map([]),
) -> @path.PathValue? raise LoaderError {
  let parent = source_directory(source_path)
  fn child(
    directory : @path.PathValue,
    name : String,
  ) -> @path.PathValue raise LoaderError {
    directory.join(@path.PathValue::new(name, directory.flavor())) catch {
      _ => raise Host(InvalidInput("invalid module candidate"))
    }
  }
  let directory = match definition.path() {
    Some(literal) => {
      let path = import_path(source_path, literal, environment~)
      let metadata = Some(@host.HostFs::metadata(host, path)) catch {
        NotFound(_) => None
        error => raise Host(error)
      }
      if metadata is Some(value) && value.is_file() {
        return Some(path)
      }
      path
    }
    None => child(parent, definition.name())
  }
  let candidates : Array[@path.PathValue] = []
  let entries = module_directory_entries(host, directory, directory_cache)
  for name in entries {
    if name == "mod.just" ||
      name.compare_ignore_ascii_case("justfile") == 0 ||
      name.compare_ignore_ascii_case(".justfile") == 0 {
      candidates.push(child(directory, name))
    }
  }
  // Rust orders paths by components. The directory component "foo" precedes
  // the sibling filename "foo.just"; all entries inside it share a parent.
  candidates.sort_by(fn(a, b) { a.as_string().lexical_compare(b.as_string()) })
  if definition.path() is None {
    let direct = definition.name() + ".just"
    if module_directory_entries(host, parent, directory_cache).contains(direct) {
      candidates.push(child(parent, direct))
    }
  }
  if candidates.length() > 1 {
    let base = parent.as_string()
    let separator = parent.flavor().separator().to_string()
    let prefix = if base.has_suffix(separator) {
      base
    } else {
      base + separator
    }
    let found = candidates.map(path => {
      match path.as_string().strip_prefix(prefix) {
        Some(relative) =>
          @path.PathValue::new(relative.to_owned(), path.flavor()) catch {
            _ => raise Host(InvalidInput("invalid relative module candidate"))
          }
        None => path
      }
    })
    raise AmbiguousModuleFile(
      module_name=definition.name(),
      source~,
      found~,
      span=definition.name_span(),
    )
  }
  match candidates.get(0) {
    Some(path) => Some(path)
    None if definition.optional() => None
    None =>
      raise ModuleFileMissing(
        module_name=definition.name(),
        source~,
        span=definition.name_span(),
      )
  }
}
