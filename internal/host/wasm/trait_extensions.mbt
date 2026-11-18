///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostScriptTemp::{
  remove_script_temp,
  create_script_temp,
}

///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostAtomicFs::{
  write_file_atomic,
}

///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostCacheStore::{
  write_cache_manifest,
  release_cache_lease,
  clean_cache,
  read_cache_manifest,
  acquire_cache_lease,
}

///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostFs::{
  file_size,
  can_execute,
  read_source,
  file_exists,
  read_file_range,
  write_file,
  canonicalize,
  read_file,
  read_dir,
  metadata,
}

///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostClock::{
  now_millis,
}

///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostEnv::{
  env_entries,
  env_get,
  current_dir,
}

///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostPlatform::{
  platform_info,
}

///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostRandom::{
  random_bytes,
}

///|
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostTerminal::{
  terminal_info,
}
