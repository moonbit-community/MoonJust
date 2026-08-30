///|
/// Compatibility surface for clients compiled against the former private
/// process-group adapter. Process execution no longer uses this path.
pub fn process_group_exec_requested() -> Bool {
  false
}

///|
pub fn enable_process_group_boundary() -> Unit {
  ()
}

///|
pub fn exec_process_group_from_args() -> Int {
  95
}
