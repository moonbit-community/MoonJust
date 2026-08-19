///|
extern "C" fn install_signal_observer() = "moonjust_async_lifecycle_install_signal_observer"

///|
extern "C" fn take_observed_signal() -> Int = "moonjust_async_lifecycle_take_observed_signal"

///|
extern "C" fn send_signal(pid : Int, signal : Int) -> Int = "moonjust_async_lifecycle_send_signal"

///|
extern "C" fn process_id() -> Int = "moonjust_async_lifecycle_process_id"

///|
extern "C" fn parent_process_id() -> Int = "moonjust_async_lifecycle_parent_process_id"

///|
extern "C" fn process_group_id() -> Int = "moonjust_async_lifecycle_process_group_id"

///|
fn init {
  if @env.get_env_var("MOONJUST_LIFECYCLE_SIGNAL_MODE") != Some("global") {
    @signal.set_global_cancellation_signals([])
    install_signal_observer()
  }
}

///|
fn signal_name(signal : Int) -> String {
  match signal {
    1 => "SIGHUP"
    2 => "SIGINT"
    3 => "SIGQUIT"
    15 => "SIGTERM"
    value => "SIGNAL_" + value.to_string()
  }
}

///|
fn process_event(event : String) -> String {
  "{\"event\":\"" +
  event +
  "\",\"pid\":" +
  process_id().to_string() +
  ",\"ppid\":" +
  parent_process_id().to_string() +
  ",\"pgid\":" +
  process_group_id().to_string() +
  "}"
}

///|
let event_mutex : @async.Mutex = Mutex()

///|
async fn emit_event(event : String) -> Unit {
  event_mutex.acquire()
  defer event_mutex.release()
  @stdio.stdout.write(@utf8.encode(event + "\n"))
}

///|
async fn cancel_process(pid : Int) -> Unit {
  emit_event(
    "{\"event\":\"cancel-handler\",\"child_pid\":" +
    pid.to_string() +
    ",\"available_cause_fields\":[\"pid\"]}",
  )
  @process.graceful_cancel(timeout=500)(pid)
}

///|
async fn run_signal_child() -> Unit {
  emit_event(process_event("child-ready"))
  while true {
    let signal = take_observed_signal()
    if signal != 0 {
      emit_event(
        "{\"event\":\"child-signal\",\"signal\":\"" +
        signal_name(signal) +
        "\",\"pid\":" +
        process_id().to_string() +
        "}",
      )
      return
    }
    @async.sleep(5)
  }
}

///|
async fn observe_parent_signals(pid : Int, first_signal : Ref[Int]) -> Unit {
  while true {
    let signal = take_observed_signal()
    if signal == 0 {
      @async.sleep(5)
      continue
    }
    if first_signal.val == 0 {
      first_signal.val = signal
    }
    emit_event(
      "{\"event\":\"parent-signal\",\"signal\":\"" +
      signal_name(signal) +
      "\",\"first_signal\":\"" +
      signal_name(first_signal.val) +
      "\",\"child_pid\":" +
      pid.to_string() +
      "}",
    )
    if signal == 15 {
      let result = send_signal(pid, signal)
      emit_event(
        "{\"event\":\"direct-forward\",\"signal\":\"SIGTERM\",\"child_pid\":" +
        pid.to_string() +
        ",\"result\":" +
        result.to_string() +
        "}",
      )
    }
  }
}

///|
fn child_command(
  scenario : String,
  executable : String,
) -> (String, Array[String]) {
  match scenario {
    "direct" => (executable, ["child"])
    "shell-exec" => ("/bin/sh", ["-cu", "exec \"$0\" child", executable])
    "shell-descendant" =>
      ("/bin/sh", ["-cu", "\"$0\" child & wait", executable])
    _ => abort("unknown lifecycle scenario")
  }
}

///|
async fn run_parent(scenario : String) -> Unit {
  let executable = @env.args()[0]
  let (program, arguments) = child_command(scenario, executable)
  @async.with_task_group() <| group => {
    let (reader, target) = @process.read_from_process()
    let process = @process.spawn(
      group,
      program,
      arguments,
      extra_env={ "MOONJUST_LIFECYCLE_SIGNAL_MODE": "observe" },
      stdout=target,
      stderr=@stdio.stderr,
      cancel_handler=CancellationHandler(cancel_process),
      no_wait=true,
    )
    emit_event(
      "{\"event\":\"parent-ready\",\"scenario\":\"" +
      scenario +
      "\",\"pid\":" +
      process_id().to_string() +
      ",\"ppid\":" +
      parent_process_id().to_string() +
      ",\"pgid\":" +
      process_group_id().to_string() +
      ",\"child_pid\":" +
      process.pid.to_string() +
      "}",
    )
    let first_signal = Ref(0)
    if @env.get_env_var("MOONJUST_LIFECYCLE_SIGNAL_MODE") != Some("global") {
      group.spawn_bg(no_wait=true, () => {
        observe_parent_signals(process.pid, first_signal)
      })
    }
    let output = group.spawn(() => {
      emit_event("{\"event\":\"pipe-reader-start\"}")
      defer reader.close()
      let bytes = reader.read_all().text()
      emit_event("{\"event\":\"pipe-reader-eof\"}")
      bytes
    })
    emit_event("{\"event\":\"process-wait-start\"}")
    let status = process.wait()
    emit_event(
      "{\"event\":\"process-wait-complete\",\"status\":" +
      status.to_string() +
      "}",
    )
    let child_output = output.wait()
    emit_event("{\"event\":\"pipe-reader-joined\"}")
    emit_event(
      "{\"event\":\"parent-complete\",\"scenario\":\"" +
      scenario +
      "\",\"status\":" +
      status.to_string() +
      ",\"first_signal\":\"" +
      signal_name(first_signal.val) +
      "\",\"child_output\":" +
      Json::string(child_output).stringify() +
      "}",
    )
  }
}

///|
async fn main {
  match @env.args()[1:] {
    ["child"] => run_signal_child()
    ["parent", scenario] => run_parent(scenario)
    _ => abort("usage: process_lifecycle.exe child | parent SCENARIO")
  }
}
