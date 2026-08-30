///|
pub(all) enum SourceSelection {
  Search
  File(@path.PathValue)
  Stdin
} derive(Debug)

///|
/// Inputs required to load one project. The request is deliberately independent
/// of CLI arguments so query and planner can share exactly the same discovery
/// semantics.
pub struct ProjectLoadRequest {
  input : ProjectInput
  selection : SourceSelection
  working_directory : @path.PathValue?
  filename : String
  ceiling : @path.PathValue?
  platform : @semantic.TargetPlatform
  environment : ArrayView[(String, String)]
}

///|
pub fn ProjectLoadRequest::new(
  input : ProjectInput,
  selection : SourceSelection,
  filename : String,
  platform : @semantic.TargetPlatform,
  environment : ArrayView[(String, String)],
  working_directory? : @path.PathValue,
  ceiling? : @path.PathValue,
) -> ProjectLoadRequest {
  {
    input,
    selection,
    working_directory,
    filename,
    ceiling,
    platform,
    environment,
  }
}

///|
fn working_directories(
  input : ProjectInput,
  selection : SourceSelection,
  working_directory : @path.PathValue?,
  resolved : @path.PathValue,
) -> @workdir.WorkingDirectoryModel raise ProjectError {
  match selection {
    Stdin =>
      @workdir.WorkingDirectoryModel::from_stdin(
        input.cwd(),
        working_directory~,
      ) catch {
        error => raise WorkingDirectory(error)
      }
    File(_) | Search =>
      @workdir.WorkingDirectoryModel::from_justfile(
        input.cwd(),
        resolved,
        working_directory~,
      ) catch {
        error => raise WorkingDirectory(error)
      }
  }
}

///|
pub fn[T : @host.HostFs] load_snapshot(
  host : T,
  request : ProjectLoadRequest,
  allow_unstable? : Bool = false,
) -> ProjectSnapshot raise ProjectError {
  let input = request.input
  if input.global_justfile() is Some(global_path) {
    let project_directory = input
      .global_project_directory()
      .unwrap_or(global_path.parent().unwrap_or(input.cwd()))
    let directories = @workdir.WorkingDirectoryModel::from_global_justfile(
      input.cwd(),
      global_path,
      project_directory,
    ) catch {
      error => raise WorkingDirectory(error)
    }
    let graph = @loader.load_graph(
      host,
      global_path,
      input.source_id(),
      platform=request.platform,
      environment=request.environment,
    ) catch {
      error => raise Load(error)
    }
    let compilation = compile_loaded_graph(
      graph,
      allow_unstable~,
      platform=request.platform,
    )
    return ProjectSnapshot::new(graph, compilation, directories)
  }
  match request.selection {
    Stdin => {
      let directories = @workdir.WorkingDirectoryModel::from_stdin(
        input.cwd(),
        working_directory=request.working_directory,
      ) catch {
        error => raise WorkingDirectory(error)
      }
      let graph = @loader.load_stdin_graph(
        host,
        input.stdin().to_owned(),
        input.source_id(),
        directories.project_directory(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
      let compilation = compile_loaded_graph(
        graph,
        allow_unstable~,
        platform=request.platform,
      )
      ProjectSnapshot::new(graph, compilation, directories)
    }
    File(path) => {
      let directories = working_directories(
        input,
        request.selection,
        request.working_directory,
        path,
      )
      let resolved = directories.justfile().unwrap()
      let graph = @loader.load_graph(
        host,
        resolved,
        input.source_id(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
      let compilation = compile_loaded_graph(
        graph,
        allow_unstable~,
        platform=request.platform,
      )
      ProjectSnapshot::new(graph, compilation, directories)
    }
    Search => {
      let options = @loader.SearchOptions::new(
        filename=request.filename,
        ceiling=request.ceiling,
      )
      let path = @loader.discover(host, input.cwd(), options~) catch {
        error => raise Load(error)
      }
      let directories = working_directories(
        input,
        request.selection,
        request.working_directory,
        path,
      )
      let graph = @loader.load_graph(
        host,
        path,
        input.source_id(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
      let compilation = compile_loaded_graph(
        graph,
        allow_unstable~,
        platform=request.platform,
      )
      ProjectSnapshot::new(graph, compilation, directories)
    }
  }
}

///|
/// Async counterpart of `load_snapshot`. The target-specific loader keeps the
/// project boundary identical for native and portable hosts while allowing the
/// Wasm host to preserve its bounded async source reads.
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn[T : @host.HostFs + @host.HostSourceReader] load_snapshot_async(
  host : T,
  request : ProjectLoadRequest,
  allow_unstable? : Bool = false,
) -> ProjectSnapshot raise ProjectError {
  let input = request.input
  if input.global_justfile() is Some(global_path) {
    let project_directory = input
      .global_project_directory()
      .unwrap_or(global_path.parent().unwrap_or(input.cwd()))
    let directories = @workdir.WorkingDirectoryModel::from_global_justfile(
      input.cwd(),
      global_path,
      project_directory,
    ) catch {
      error => raise WorkingDirectory(error)
    }
    let graph = @loader.load_graph_async(
      host,
      global_path,
      input.source_id(),
      platform=request.platform,
      environment=request.environment,
    ) catch {
      error => raise Load(error)
    }
    let compilation = compile_loaded_graph(
      graph,
      allow_unstable~,
      platform=request.platform,
    )
    return ProjectSnapshot::new(graph, compilation, directories)
  }
  match request.selection {
    Stdin => {
      let directories = @workdir.WorkingDirectoryModel::from_stdin(
        input.cwd(),
        working_directory=request.working_directory,
      ) catch {
        error => raise WorkingDirectory(error)
      }
      let graph = @loader.load_stdin_graph_async(
        host,
        input.stdin().to_owned(),
        input.source_id(),
        directories.project_directory(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
      let compilation = compile_loaded_graph(
        graph,
        allow_unstable~,
        platform=request.platform,
      )
      ProjectSnapshot::new(graph, compilation, directories)
    }
    File(path) => {
      let directories = working_directories(
        input,
        request.selection,
        request.working_directory,
        path,
      )
      let resolved = directories.justfile().unwrap()
      let graph = @loader.load_graph_async(
        host,
        resolved,
        input.source_id(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
      let compilation = compile_loaded_graph(
        graph,
        allow_unstable~,
        platform=request.platform,
      )
      ProjectSnapshot::new(graph, compilation, directories)
    }
    Search => {
      let options = @loader.SearchOptions::new(
        filename=request.filename,
        ceiling=request.ceiling,
      )
      let path = @loader.discover(host, input.cwd(), options~) catch {
        error => raise Load(error)
      }
      let directories = working_directories(
        input,
        request.selection,
        request.working_directory,
        path,
      )
      let graph = @loader.load_graph_async(
        host,
        path,
        input.source_id(),
        platform=request.platform,
        environment=request.environment,
      ) catch {
        error => raise Load(error)
      }
      let compilation = compile_loaded_graph(
        graph,
        allow_unstable~,
        platform=request.platform,
      )
      ProjectSnapshot::new(graph, compilation, directories)
    }
  }
}

///|
#cfg(target="native")
pub fn[T : @host.HostFs] load_snapshot_async(
  host : T,
  request : ProjectLoadRequest,
  allow_unstable? : Bool = false,
) -> ProjectSnapshot raise ProjectError {
  load_snapshot(host, request, allow_unstable~)
}
