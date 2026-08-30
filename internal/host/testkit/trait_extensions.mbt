///|
pub extend FakeHost with @host.HostAsyncOutput::{write_output}

///|
pub extend FakeHost with @host.HostAsyncProcess::{run_process_async}

///|
pub extend FakeHost with @host.HostAsyncScriptTemp::{
  remove_script_temp_async,
  create_script_temp_async,
}

///|
pub extend FakeHost with @host.HostAtomicFs::{write_file_atomic}

///|
pub extend FakeHost with @host.HostCacheStore::{
  write_cache_manifest,
  release_cache_lease,
  clean_cache,
  read_cache_manifest,
  acquire_cache_lease,
}

///|
pub extend FakeHost with @host.HostClock::{now_millis}

///|
pub extend FakeHost with @host.HostEnv::{env_entries, env_get, current_dir}

///|
pub extend FakeHost with @host.HostExecutable::{set_executable}

///|
pub extend FakeHost with @host.HostFs::{
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
pub extend FakeHost with @host.HostPlatform::{platform_info}

///|
pub extend FakeHost with @host.HostProcess::{run_process}

///|
pub extend FakeHost with @host.HostRandom::{random_bytes}

///|
pub extend FakeHost with @host.HostScriptTemp::{
  remove_script_temp,
  create_script_temp,
}

///|
pub extend FakeHost with @host.HostSignal::{pending_signal}

///|
pub extend FakeHost with @host.HostSourceReader::{read_source}

///|
pub extend FakeHost with @host.HostTemp::{remove_temp_file, create_temp_file}

///|
pub extend FakeHost with @host.HostTerminal::{terminal_info}
