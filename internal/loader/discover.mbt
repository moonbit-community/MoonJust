///|
/// Discover a justfile without consulting global process state.
pub async fn[T : @host.HostFs] discover(
  host : T,
  start : @path.PathValue,
  options~ : SearchOptions = SearchOptions::new(),
) -> @path.PathValue raise LoaderError {
  match options.explicit() {
    Some(path) => {
      let exists = @host.HostFs::file_exists(host, path) catch {
        error => raise Host(error)
      }
      if !exists {
        raise ExplicitFileMissing(path~)
      }
      return path
    }
    None => ()
  }
  let mut current = start
  while true {
    let candidate = find_candidate(host, current, options.filename()) catch {
      Host(NotFound(path)) => raise MissingSearchDirectory(path)
      error => raise error
    }
    match candidate {
      Some(path) => return path
      None => ()
    }
    match options.ceiling() {
      Some(ceiling) if current == ceiling => break
      _ => ()
    }
    match parent_or_self(current) {
      None => break
      Some(parent) if parent == current => break
      Some(parent) => current = parent
    }
  }
  match options.global() {
    Some(global) => {
      let exists = @host.HostFs::file_exists(host, global) catch {
        error => raise Host(error)
      }
      if exists {
        return global
      }
    }
    None => ()
  }
  raise NoJustfileFound(start~, filename=options.filename())
}

///|
/// Load an in-memory source through the same parser boundary as filesystem input.
pub fn load_bytes(
  bytes : Bytes,
  source_id : @source.SourceId,
  display_name : String,
  environment~ : ArrayView[(String, String)] = [],
) -> LoadedSource raise LoaderError {
  let path = @path.PathValue::new(display_name, Unix) catch {
    _ => raise Host(InvalidInput("invalid source display name"))
  }
  let source = source_from_file_bytes(bytes, source_id, path)
  let ast = parse_loaded_source(source, environment~)
  {
    path,
    canonical_path: path,
    source,
    ast,
    parent: None,
    import_span: None,
    relation: RootSource,
    module_path: @modulepath.ModulePath::root(),
    module_directory: source_directory(path),
  }
}

///|
/// Load a Markdown source after source-aware fenced-just tangling.
pub fn load_markdown(
  bytes : Bytes,
  source_id : @source.SourceId,
  display_name~ : String = "README.md",
  environment~ : ArrayView[(String, String)] = [],
) -> LoadedSource raise LoaderError {
  let raw = @source.Source::from_bytes(source_id, display_name, bytes) catch {
    error => raise InvalidSource(error)
  }
  let tangled = @formatter.tangle(raw) catch {
    _ => raise Host(InvalidInput("invalid Markdown source"))
  }
  let source = tangled.source()
  let ast = parse_loaded_source(source, environment~)
  let path = @path.PathValue::new(display_name, Unix) catch {
    _ => raise Host(InvalidInput("invalid Markdown display name"))
  }
  {
    path,
    canonical_path: path,
    source,
    ast,
    parent: None,
    import_span: None,
    relation: RootSource,
    module_path: @modulepath.ModulePath::root(),
    module_directory: source_directory(path),
  }
}

///|
/// Discover and load using the caller's current directory.
pub async fn[T : @host.HostFs + @host.HostEnv] load_from_current_dir(
  host : T,
  source_id : @source.SourceId,
  options~ : SearchOptions = SearchOptions::new(),
) -> LoadedSource raise LoaderError {
  let cwd = @host.HostEnv::current_dir(host) catch {
    error => raise Host(error)
  }
  let path = discover(host, cwd, options~)
  let environment = @host.HostEnv::env_entries(host) catch {
    error => raise Host(error)
  }
  load(host, path, source_id, environment~)
}

///|
fn import_path(
  parent : @path.PathValue,
  literal : @syntax.StringLiteral,
  environment~ : ArrayView[(String, String)] = [],
) -> @path.PathValue raise LoaderError {
  let mut value = literal.cooked()
  if value.has_prefix("~/") || value.has_prefix("~\\") {
    let home_name = if parent.flavor() == Windows {
      "USERPROFILE"
    } else {
      "HOME"
    }
    for entry in environment {
      if entry.0 == home_name {
        value = entry.1 + value[1:].to_owned()
        break
      }
    }
  }
  let child = @path.PathValue::new(value, parent.flavor()) catch {
    _ => raise Host(InvalidInput("invalid import path"))
  }
  let directory = parent.parent().unwrap_or(parent)
  directory.join(child) catch {
    _ => raise Host(InvalidInput("import path flavor mismatch"))
  }
}

///|
/// Metadata is scoped to one graph load. Recipes execute after the graph is
/// discarded, so a file changed by a recipe can never be observed through it.
