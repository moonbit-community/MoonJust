///|
#deprecated
pub extend CacheLease with Debug::{to_repr}

///|
#deprecated
pub extend CacheLease with Eq::{not_equal, equal}

///|
#deprecated
pub extend HostError with Debug::{to_repr}

///|
#deprecated
pub extend HostError with Eq::{not_equal, equal}

///|
pub extend FakeHost with HostAsyncOutput::{write_output}

///|
pub extend FakeHost with HostAsyncProcess::{run_process_async}

///|
pub extend FakeHost with HostAsyncScriptTemp::{
  remove_script_temp_async,
  create_script_temp_async,
}

///|
pub extend FakeHost with HostAtomicFs::{write_file_atomic}

///|
pub extend FakeHost with HostCacheStore::{
  write_cache_manifest,
  release_cache_lease,
  clean_cache,
  read_cache_manifest,
  acquire_cache_lease,
}

///|
pub extend FakeHost with HostClock::{now_millis}

///|
pub extend FakeHost with HostEnv::{env_entries, env_get, current_dir}

///|
pub extend FakeHost with HostExecutable::{set_executable}

///|
pub extend FakeHost with HostFs::{
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
pub extend FakeHost with HostPlatform::{platform_info}

///|
pub extend FakeHost with HostProcess::{run_process}

///|
pub extend FakeHost with HostRandom::{random_bytes}

///|
pub extend FakeHost with HostScriptTemp::{
  remove_script_temp,
  create_script_temp,
}

///|
pub extend FakeHost with HostSignal::{pending_signal}

///|
pub extend FakeHost with HostSourceReader::{read_source}

///|
pub extend FakeHost with HostTemp::{remove_temp_file, create_temp_file}

///|
pub extend FakeHost with HostTerminal::{terminal_info}

///|
#deprecated
pub extend CommandSpec with Debug::{to_repr}

///|
#deprecated
pub extend CommandSpec with Eq::{not_equal, equal}

///|
#deprecated
pub extend FileMetadata with Debug::{to_repr}

///|
#deprecated
pub extend FileMetadata with Eq::{not_equal, equal}

///|
#deprecated
pub extend HostCapability with Debug::{to_repr}

///|
#deprecated
pub extend HostCapability with Eq::{not_equal, equal}

///|
#deprecated
pub extend HostCapability with Hash::{hash, hash_combine}

///|
#deprecated
pub extend OperatingSystem with Debug::{to_repr}

///|
#deprecated
pub extend OperatingSystem with Eq::{not_equal, equal}

///|
#deprecated
pub extend OperatingSystem with Hash::{hash, hash_combine}

///|
#deprecated
pub extend OutputStream with Debug::{to_repr}

///|
#deprecated
pub extend OutputStream with Eq::{not_equal, equal}

///|
#deprecated
pub extend PlatformInfo with Debug::{to_repr}

///|
#deprecated
pub extend PlatformInfo with Eq::{not_equal, equal}

///|
#deprecated
pub extend ProcessResult with Debug::{to_repr}

///|
#deprecated
pub extend ProcessResult with Eq::{not_equal, equal}

///|
#deprecated
pub extend ProcessTermination with Debug::{to_repr}

///|
#deprecated
pub extend ProcessTermination with Eq::{not_equal, equal}

///|
#deprecated
pub extend SignalKind with Debug::{to_repr}

///|
#deprecated
pub extend SignalKind with Eq::{not_equal, equal}

///|
#deprecated
pub extend StdioBehavior with Debug::{to_repr}

///|
#deprecated
pub extend StdioBehavior with Eq::{not_equal, equal}

///|
#deprecated
pub extend TerminalInfo with Debug::{to_repr}

///|
#deprecated
pub extend TerminalInfo with Eq::{not_equal, equal}
