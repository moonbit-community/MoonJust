///|
fn global_child(
  base : @path.PathValue,
  components : ArrayView[String],
) -> @path.PathValue raise ApplicationError {
  let mut path = base
  for component in components {
    let child = @path.PathValue::new(component, base.flavor()) catch {
      error => raise Path(error)
    }
    path = path.join(child) catch { error => raise Path(error) }
  }
  path
}

///|
fn[E : @host.HostEnv] global_environment_path(
  environment : E,
  name : String,
  flavor : @path.PathFlavor,
) -> @path.PathValue? raise ApplicationError {
  let value = try @host.HostEnv::env_get(environment, name) catch {
    error => raise Host(error)
  } noraise {
    result => result
  }
  match value {
    Some(value) =>
      Some(
        @path.PathValue::new(value, flavor) catch {
          error => raise Path(error)
        },
      )
    None => None
  }
}

///|
fn[F : @host.HostFs] find_global_candidate(
  filesystem : F,
  candidates : Array[(@path.PathValue, String)],
) -> @path.PathValue? raise ApplicationError {
  for candidate in candidates {
    let directory = candidate.0
    let expected = candidate.1
    let entries = try @host.HostFs::read_dir(filesystem, directory) catch {
      _ => continue
    } noraise {
      value => value
    }
    for entry in entries {
      if entry.to_lower() == expected {
        return Some(global_child(directory, [entry]))
      }
    }
  }
  None
}

///|
fn[F : @host.HostFs] global_project_root(
  filesystem : F,
  start : @path.PathValue,
  ceiling : @path.PathValue?,
) -> @path.PathValue raise ApplicationError {
  let markers = [".bzr", ".git", ".hg", ".svn", "_darcs"]
  let mut current = start
  while true {
    let entries = @host.HostFs::read_dir(filesystem, current) catch {
      error => raise Host(error)
    }
    for entry in entries {
      if markers.contains(entry) {
        return current
      }
    }
    if ceiling == Some(current) {
      break
    }
    match current.parent() {
      Some(parent) if parent != current => current = parent
      _ => break
    }
  }
  start
}

///|
/// Resolve just 1.57.0's platform-specific global search before normal
/// application loading. The returned context keeps the invocation project cwd
/// separate from the user-configuration justfile path.
pub fn[F : @host.HostFs, E : @host.HostEnv + @host.HostPlatform] resolve_global_context(
  filesystem : F,
  environment : E,
  arguments : @cli.CliArguments,
  context : @project.ProjectInput,
) -> @project.ProjectInput raise ApplicationError {
  guard arguments.flag("global-justfile") else { return context }
  if arguments.command() == InitCommand {
    raise Query("cannot initialize global justfile")
  }
  for argument in arguments.positional() {
    if argument.contains("/") || argument.contains("\\") {
      raise Query(
        "path-prefixed recipes may not be used with `--global-justfile`, " +
        "`--working-directory`, or `--justfile`",
      )
    }
  }
  let platform = @host.HostPlatform::platform_info(environment) catch {
    error => raise Host(error)
  }
  let flavor = platform.path_flavor()
  let home = global_environment_path(environment, "HOME", flavor)
  let candidates : Array[(@path.PathValue, String)] = []
  match platform.operating_system() {
    Macos =>
      match home {
        Some(path) =>
          candidates.push(
            (
              global_child(path, ["Library", "Application Support", "just"]),
              "justfile",
            ),
          )
        None => ()
      }
    Windows =>
      match global_environment_path(environment, "APPDATA", flavor) {
        Some(path) =>
          candidates.push((global_child(path, ["just"]), "justfile"))
        None => ()
      }
    Linux | Other(_) => {
      let xdg = global_environment_path(environment, "XDG_CONFIG_HOME", flavor)
      match xdg {
        Some(path) if path.is_absolute() =>
          candidates.push((global_child(path, ["just"]), "justfile"))
        _ if platform.operating_system() == Linux =>
          match home {
            Some(path) =>
              candidates.push(
                (global_child(path, [".config", "just"]), "justfile"),
              )
            None => ()
          }
        _ => ()
      }
      if platform.operating_system() is Other(_) {
        match home {
          Some(path) =>
            candidates.push(
              (
                global_child(path, ["Library", "Application Support", "just"]),
                "justfile",
              ),
            )
          None => ()
        }
      }
    }
  }
  match home {
    Some(directory) => {
      candidates.push(
        (global_child(directory, [".config", "just"]), "justfile"),
      )
      candidates.push((directory, "justfile"))
      candidates.push((directory, ".justfile"))
    }
    None => ()
  }
  guard find_global_candidate(filesystem, candidates) is Some(justfile) else {
    raise Query("global justfile not found")
  }
  let project = global_project_root(
    filesystem,
    context.cwd(),
    ceiling_argument(arguments, context.cwd()),
  )
  context.with_global_justfile(justfile, project)
}
