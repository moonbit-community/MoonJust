///|
pub extend PolicyFs with @ZSeanYves/MoonJust/internal/host.HostAtomicFs::{
  write_file_atomic,
}

///|
pub extend PolicyFs with @ZSeanYves/MoonJust/internal/host.HostFs::{
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
pub extend PolicyFs with @ZSeanYves/MoonJust/internal/host.HostSourceReader::{
  read_source,
}
