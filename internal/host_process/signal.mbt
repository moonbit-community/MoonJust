///|
/// Native Unix signal state. The C boundary only writes signal numbers to the
/// async pipe; all policy and process ownership stays in this package.
#cfg(all(target="native", not(platform="windows")))
priv struct ActiveSignalChild {
  pid : Int
  description : String
}

///|
#cfg(all(target="native", not(platform="windows")))
priv struct SignalRuntime {
  read : @pipe.PipeRead
  write : @pipe.PipeWrite
  children : Array[ActiveSignalChild]
  mut first_signal : Int?
}

///|
#cfg(all(target="native", not(platform="windows")))
let signal_runtime : Ref[SignalRuntime?] = Ref(None)

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn prepare_signal_forwarding_ffi() = "moonjust_prepare_signal_forwarding"

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn install_signal_pipe_ffi(fd : @types.Fd) = "moonjust_install_signal_pipe"

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn unblock_signal_mask_ffi() = "moonjust_unblock_forwarded_signals"

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn signal_pipe_overflow_ffi() -> Int = "moonjust_signal_pipe_overflow"

///|
#cfg(all(target="native", not(platform="windows")))
extern "C" fn current_process_id_ffi() -> Int = "moonjust_current_process_id"

///|
#cfg(all(target="native", not(platform="windows")))
pub fn prepare_signal_forwarding() -> Unit {
  ignore(@pipe.pipe)
  @signal.set_global_cancellation_signals([])
  prepare_signal_forwarding_ffi()
}

///|
#cfg(any(target="wasm", platform="windows"))
pub fn prepare_signal_forwarding() -> Unit {
  ignore(@pipe.pipe)
  ()
}

///|
#cfg(all(target="native", not(platform="windows")))
pub fn[X] configure_signal_forwarding(
  group : @async.TaskGroup[X],
  observe_children : Bool,
) -> @host.HostError? {
  let (read, write) = try @pipe.pipe() catch {
    _ => return Some(InvalidInput("failed to create signal pipe"))
  } noraise {
    value => value
  }
  // Async creates its signal-wait worker while the event loop starts. Reset
  // the current thread's cancellation mask after that initialization as well
  // as during package setup, so process-directed signals reach our pipe
  // handler instead of cancelling the root task.
  @signal.set_global_cancellation_signals([])
  install_signal_pipe_ffi(write.fd())
  unblock_signal_mask_ffi()
  let state = { read, write, children: [], first_signal: None }
  ignore(state.write.fd())
  signal_runtime.val = Some(state)
  if observe_children {
    group.spawn_bg(no_wait=true, allow_failure=true, () => observe_signals())
  }
  None
}

///|
#cfg(any(target="wasm", platform="windows"))
pub fn[X] configure_signal_forwarding(
  _group : @async.TaskGroup[X],
  _observe_children : Bool,
) -> @host.HostError? {
  @signal.set_global_cancellation_signals([SIGINT, SIGTERM, SIGHUP, SIGBREAK])
  None
}

///|
#cfg(all(target="native", not(platform="windows")))
fn signal_name(number : Int) -> String {
  match number {
    1 => "SIGHUP"
    2 => "SIGINT"
    3 => "SIGQUIT"
    15 => "SIGTERM"
    29 => "SIGINFO"
    value => "SIG" + value.to_string()
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
fn add_signal_child(pid : Int, description : String) -> Unit {
  guard signal_runtime.val is Some(state) else { return }
  state.children.push({ pid, description })
}

///|
#cfg(all(target="native", not(platform="windows")))
fn remove_signal_child(pid : Int) -> Unit {
  guard signal_runtime.val is Some(state) else { return }
  for index in 0..<state.children.length() {
    if state.children[index].pid == pid {
      ignore(state.children.remove(index))
      break
    }
  }
  if state.children.is_empty() {
    state.first_signal = None
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
fn caught_signal() -> Int? {
  match signal_runtime.val {
    Some(state) => state.first_signal
    None => None
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn write_signal_info(state : SignalRuntime) -> Unit {
  let id = current_process_id_ffi()
  if state.children.is_empty() {
    try
      @stdio.stderr.write(
        @utf8.encode("just " + id.to_string() + ": no child processes\n"),
      )
    catch {
      _ => ()
    } noraise {
      _ => ()
    }
    return
  }
  let count = state.children.length()
  let label = if count == 1 { "process" } else { "processes" }
  let output = StringBuilder()
  output.write_string(
    "just " +
    id.to_string() +
    ": " +
    count.to_string() +
    " child " +
    label +
    ":\n",
  )
  for child in state.children {
    output.write_string(child.pid.to_string() + ": " + child.description + "\n")
  }
  try @stdio.stderr.write(@utf8.encode(output.to_string())) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn handle_signal(state : SignalRuntime, signal : Int) -> Unit {
  if signal == 1 || signal == 2 || signal == 3 || signal == 15 {
    if state.first_signal is None {
      state.first_signal = Some(signal)
    }
  }
  if signal == 15 {
    for child in state.children {
      // Signal the direct child without cancelling its async wait task. The
      // wait must observe the real -SIGTERM status for just's exit mapping.
      @process.graceful_cancel(timeout=5000, signal=SIGTERM)(child.pid)
    }
  } else if signal == 29 {
    write_signal_info(state)
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
async fn observe_signals() -> Unit {
  guard signal_runtime.val is Some(state) else { return }
  for ;; {
    guard state.read.read_some(max_len=1) is Some(bytes) else { return }
    for byte in bytes {
      handle_signal(state, byte.to_int())
    }
    if signal_pipe_overflow_ffi() != 0 {
      // The pipe can only overflow under an external signal storm. The first
      // signal remains authoritative; later delivery is intentionally coalesced.
      ()
    }
  }
}

///|
#cfg(all(target="native", not(platform="windows")))
pub async fn wait_for_signal_request() -> String? {
  guard signal_runtime.val is Some(state) else { return None }
  for ;; {
    guard state.read.read_some(max_len=1) is Some(bytes) else { return None }
    for byte in bytes {
      let signal = byte.to_int()
      if signal == 1 || signal == 2 || signal == 3 || signal == 15 {
        return Some(signal_name(signal))
      }
    }
  }
}

///|
#cfg(any(target="wasm", platform="windows"))
pub async fn wait_for_signal_request() -> String? {
  @async.sleep(0)
  None
}

///|
#cfg(all(target="native", not(platform="windows")))
fn signal_process_status(status : Int) -> Int {
  match caught_signal() {
    Some(signal) => -(256 + signal)
    None => status
  }
}
