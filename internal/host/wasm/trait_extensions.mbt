///|
pub extend ReadOnlyFs with @ZSeanYves/MoonJust/internal/host.HostAtomicFs::{
  write_file_atomic,
}

///|
pub extend ReadOnlyFs with @ZSeanYves/MoonJust/internal/host.HostFs::{
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
pub extend ReadOnlyFs with @ZSeanYves/MoonJust/internal/host.HostSourceReader::{
  read_source,
}

///|
pub extend ReadOnlyFs with @ZSeanYves/MoonJust/internal/host.HostTemp::{
  remove_temp_file,
  create_temp_file,
}

///|
#cfg(target="wasm")
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostAsyncScriptTemp::{
  remove_script_temp_async,
  create_script_temp_async,
}

///|
#cfg(target="wasm")
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostAtomicFs::{
  write_file_atomic,
}

///|
#cfg(target="wasm")
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostCacheStore::{
  write_cache_manifest,
  release_cache_lease,
  clean_cache,
  read_cache_manifest,
  acquire_cache_lease,
}

///|
#cfg(target="wasm")
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostFs::{
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
#cfg(target="wasm")
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostSourceReader::{
  read_source,
}

///|
#cfg(target="wasm")
pub extend ExecutionFs with @ZSeanYves/MoonJust/internal/host.HostTemp::{
  remove_temp_file,
  create_temp_file,
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub extend PortableHost with @ZSeanYves/MoonJust/internal/host.HostClock::{
  now_millis,
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub extend PortableHost with @ZSeanYves/MoonJust/internal/host.HostEnv::{
  env_entries,
  env_get,
  current_dir,
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub extend PortableHost with @ZSeanYves/MoonJust/internal/host.HostFs::{
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
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub extend PortableHost with @ZSeanYves/MoonJust/internal/host.HostPlatform::{
  platform_info,
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub extend PortableHost with @ZSeanYves/MoonJust/internal/host.HostRandom::{
  random_bytes,
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub extend PortableHost with @ZSeanYves/MoonJust/internal/host.HostSourceReader::{
  read_source,
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub extend PortableHost with @ZSeanYves/MoonJust/internal/host.HostTerminal::{
  terminal_info,
}
