///|
fn[T : @host.HostFs] metadata_cached(
  host : T,
  path : @path.PathValue,
  cache : Map[String, @host.FileMetadata],
) -> @host.FileMetadata raise LoaderError {
  let key = path.as_string()
  match cache.get(key) {
    Some(value) => value
    None => {
      let value = @host.HostFs::metadata(host, path) catch {
        error => raise Host(error)
      }
      cache[key] = value
      value
    }
  }
}

///|
fn[T : @host.HostFs] push_existing_module_candidate(
  host : T,
  candidates : Array[@path.PathValue],
  path : @path.PathValue,
  metadata_cache? : Map[String, @host.FileMetadata] = Map([]),
) -> Unit raise LoaderError {
  let exists = @host.HostFs::file_exists(host, path) catch {
    error => raise Host(error)
  }
  if !exists {
    return
  }
  let metadata = metadata_cached(host, path, metadata_cache)
  if !metadata.is_file() {
    return
  }
  let canonical = @host.HostFs::canonicalize(host, path) catch {
    error => raise Host(error)
  }
  for candidate in candidates {
    let existing = @host.HostFs::canonicalize(host, candidate) catch {
      error => raise Host(error)
    }
    if existing == canonical {
      return
    }
  }
  candidates.push(path)
}

///|
fn lowercase_ascii(value : String) -> String {
  let builder = StringBuilder()
  for character in value {
    if character.is_ascii_uppercase() {
      builder.write_char((character.to_int() + 32).to_char().unwrap())
    } else {
      builder.write_char(character)
    }
  }
  builder.to_string()
}

///|
fn[T : @host.HostFs] push_module_directory_candidates(
  host : T,
  candidates : Array[@path.PathValue],
  directory : @path.PathValue,
  metadata_cache? : Map[String, @host.FileMetadata] = Map([]),
) -> Unit raise LoaderError {
  let exists = @host.HostFs::file_exists(host, directory) catch {
    error => raise Host(error)
  }
  if exists {
    let metadata = try metadata_cached(host, directory, metadata_cache) catch {
      Host(NotFound(_)) => return
      error => raise error
    } noraise {
      value => value
    }
    if !metadata.is_directory() {
      return
    }
  }
  let entries = try @host.HostFs::read_dir(host, directory) catch {
    NotFound(_) => return
    error => raise Host(error)
  } noraise {
    values => values
  }
  for entry in entries {
    let normalized = lowercase_ascii(entry)
    if entry != "mod.just" &&
      normalized != "justfile" &&
      normalized != ".justfile" {
      continue
    }
    let child = @path.PathValue::new(entry, directory.flavor()) catch {
      _ => raise Host(InvalidInput("invalid module candidate"))
    }
    push_existing_module_candidate(
      host,
      candidates,
      directory.join(child) catch {
        _ => raise Host(InvalidInput("module candidate flavor mismatch"))
      },
      metadata_cache~,
    )
  }
}

///|
fn[T : @host.HostFs] resolve_module_file(
  host : T,
  source_path : @path.PathValue,
  definition : @syntax.Module,
  environment? : ArrayView[(String, String)] = [],
  metadata_cache? : Map[String, @host.FileMetadata] = Map([]),
) -> @path.PathValue? raise LoaderError {
  let directory = source_path.parent().unwrap_or(source_path)
  let candidates : Array[@path.PathValue] = []
  match definition.path() {
    Some(literal) => {
      let explicit = import_path(source_path, literal, environment~)
      push_existing_module_candidate(
        host,
        candidates,
        explicit,
        metadata_cache~,
      )
      if candidates.is_empty() {
        push_module_directory_candidates(
          host,
          candidates,
          explicit,
          metadata_cache~,
        )
      }
    }
    None => {
      let direct = @path.PathValue::new(
        definition.name() + ".just",
        directory.flavor(),
      ) catch {
        _ => raise Host(InvalidInput("invalid module candidate"))
      }
      push_existing_module_candidate(
        host,
        candidates,
        directory.join(direct) catch {
          _ => raise Host(InvalidInput("module candidate flavor mismatch"))
        },
        metadata_cache~,
      )
      let module_directory = directory.join(
        @path.PathValue::new(definition.name(), directory.flavor()) catch {
          _ => raise Host(InvalidInput("invalid module directory"))
        },
      ) catch {
        _ => raise Host(InvalidInput("module directory flavor mismatch"))
      }
      push_module_directory_candidates(
        host,
        candidates,
        module_directory,
        metadata_cache~,
      )
    }
  }
  if candidates.length() > 1 {
    raise AmbiguousModuleFile(
      module_name=definition.name(),
      found=candidates,
      span=definition.name_span(),
    )
  }
  match candidates.get(0) {
    Some(path) => Some(path)
    None if definition.optional() => None
    None =>
      raise ModuleFileMissing(
        module_name=definition.name(),
        span=@source.Span::new(
          definition.span().source_id(),
          definition.span().start_byte() +
          (if definition.optional() { 5 } else { 4 }),
          definition.span().start_byte() +
          (if definition.optional() { 5 } else { 4 }) +
          definition.name().length(),
        ) catch {
          _ => definition.span()
        },
      )
  }
}
