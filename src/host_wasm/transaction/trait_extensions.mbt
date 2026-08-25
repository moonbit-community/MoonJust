///|
pub extend PolicyFs with @ZSeanYves/MoonJust/src/host.HostAtomicFs::{
  write_file_atomic,
}

///|
pub extend PolicyFs with @ZSeanYves/MoonJust/src/host.HostFs::{
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
pub extend PolicyFs with @ZSeanYves/MoonJust/src/host.HostSourceReader::{
  read_source,
}
