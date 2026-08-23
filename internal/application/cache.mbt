///|
/// Clear recognized cache manifests for the selected project. Permanent lock
/// files and unrelated directory entries are intentionally preserved.
#warnings("-unused_trait_bound")
pub async fn[T : @host.HostFs + @host.HostSourceReader + @host.HostCacheStore] execute_clean_command(
  host : T,
  arguments : @cli.CliArguments,
  context : ApplicationContext,
) -> @cli.ApplicationResponse raise ApplicationError {
  if arguments.command() != CleanCommand {
    raise UnsupportedCommand("cache clean")
  }
  let recipe_prefix = if arguments.positional().is_empty() {
    None
  } else {
    Some(arguments.positional().join("::"))
  }
  let (_, directories) = load_input_with_directories_async(
    host, arguments, context,
  )
  let directory = cache_directory(directories.module_directory())
  let existed = @host.HostFs::file_exists(host, directory) catch {
    error => raise Host(error)
  }
  let removed = @host.HostCacheStore::clean_cache(
    host, directory, recipe_prefix,
  ) catch {
    error => raise Host(error)
  }
  let stderr = if arguments.flag("quiet") {
    b""
  } else if !existed {
    @utf8.encode("recipe cache not found\n")
  } else {
    let noun = if removed == 1 { "cache entry" } else { "cache entries" }
    @utf8.encode("removed \{removed} \{noun}\n")
  }
  @cli.ApplicationResponse::success(stderr~)
}
