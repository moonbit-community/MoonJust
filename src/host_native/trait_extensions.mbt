///|
#cfg(any(target="native", target="llvm"))
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostAsyncScriptTemp::{
  remove_script_temp_async,
  create_script_temp_async,
}

///|
#cfg(any(target="native", target="llvm"))
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostCacheStore::{
  write_cache_manifest,
  release_cache_lease,
  clean_cache,
  read_cache_manifest,
  acquire_cache_lease,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostClock::{now_millis}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostAtomicFs::{
  write_file_atomic,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostEnv::{
  env_entries,
  env_get,
  current_dir,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostExecutable::{
  set_executable,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostFs::{
  file_exists,
  persist_temp_file,
  read_file_range,
  write_file,
  canonicalize,
  read_file,
  read_dir,
  metadata,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostPlatform::{
  platform_info,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostRandom::{random_bytes}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostScriptTemp::{
  remove_script_temp,
  create_script_temp,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostTemp::{
  remove_temp_file,
  create_temp_file,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostTerminal::{
  terminal_info,
}

///|
pub extend NativeFs with @ZSeanYves/MoonJust/src/host.HostSourceReader::{
  read_source,
}
