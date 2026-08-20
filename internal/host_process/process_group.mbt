///|
/// Native Unix process-group support is deliberately kept outside async's
/// process runtime. async still owns process creation, waiting, and pipes.
#cfg(all(target="native", not(platform="windows")))
const PROCESS_GROUP_ENV : String = "MOONJUST_INTERNAL_PROCESS_GROUP"

///|
#cfg(all(target="native", not(platform="windows")))
const PROCESS_GROUP_FLAG : String = "--moonjust-process-group-exec"

///|
#cfg(all(target="native", not(platform="windows")))
let process_group_boundary_enabled : Ref[Bool] = Ref(false)

///|
#cfg(all(target="native", not(platform="windows")))
#borrow(payload)
extern "C" fn process_group_exec_ffi(payload : Bytes, length : Int) -> Int = "moonjust_process_group_exec"

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn process_group_id_ffi(pid : Int) -> Int = "moonjust_process_group_id"

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn process_group_signal_ffi(group : Int, signal : Int) -> Int = "moonjust_process_group_signal"

///|
#cfg(all(target="native", not(platform="windows")))
pub fn process_group_exec_requested() -> Bool {
  @env.get_env_var(PROCESS_GROUP_ENV) == Some("1") &&
  @env.args().get(1) == Some(PROCESS_GROUP_FLAG)
}

///|
#cfg(all(target="native", not(platform="windows")))
pub fn enable_process_group_boundary() -> Unit {
  process_group_boundary_enabled.val = true
}

///|
#cfg(all(target="native", not(platform="windows")))
fn process_group_boundary_is_enabled() -> Bool {
  process_group_boundary_enabled.val
}

///|
#cfg(all(target="native", not(platform="windows")))
fn process_group_payload(args : ArrayView[String]) -> Bytes {
  let payload = Buffer()
  for argument in args {
    payload.write_bytes(@utf8.encode(argument))
    payload.write_byte(0)
  }
  payload.to_bytes()
}

///|
#cfg(all(target="native", not(platform="windows")))
pub fn exec_process_group_from_args() -> Int {
  let args = @env.args()
  guard args.length() >= 3 && args[1] == PROCESS_GROUP_FLAG else { return 22 }
  guard args[2] != "" else { return 22 }
  for argument in args[2:] {
    if argument.contains("\u{0000}") {
      return 22
    }
  }
  let payload = process_group_payload(args[2:])
  @env.unset_env_var(PROCESS_GROUP_ENV)
  process_group_exec_ffi(payload, payload.length())
}

///|
#cfg(all(target="native", not(platform="windows")))
fn process_group_id(pid : Int) -> Int {
  process_group_id_ffi(pid)
}

///|
#cfg(all(target="native", not(platform="windows")))
fn signal_process_group(group : Int, signal : Int) -> Int {
  process_group_signal_ffi(group, signal)
}

///|
#cfg(all(target="native", not(platform="windows")))
fn process_group_alive(group : Int) -> Bool {
  signal_process_group(group, 0) == 0
}

///|
#cfg(any(target="wasm", platform="windows"))
pub fn process_group_exec_requested() -> Bool {
  false
}

///|
#cfg(any(target="wasm", platform="windows"))
pub fn enable_process_group_boundary() -> Unit {
  ()
}

///|
#cfg(any(target="wasm", platform="windows"))
pub fn exec_process_group_from_args() -> Int {
  95
}
