///|
/// Fine-grained timing for Wasm performance experiments. The normal path
/// leaves the trace disabled and does not allocate or write diagnostics.
let perf_detail_enabled : Ref[Bool?] = Ref(None)

///|
let perf_detail_started : Ref[Int64?] = Ref(None)

///|
let perf_detail_events : Array[(String, Int64)] = []

///|
fn perf_detail_is_enabled() -> Bool {
  match perf_detail_enabled.val {
    Some(value) => value
    None => {
      let value = @env.get_env_var("MOONJUST_PERF_TRACE") == Some("1")
      perf_detail_enabled.val = Some(value)
      value
    }
  }
}

///|
/// Record a stage timestamp. The disabled path performs only one cached branch.
fn perf_detail_mark(name : String) -> Unit {
  if !perf_detail_is_enabled() {
    return
  }
  let started = match perf_detail_started.val {
    Some(value) => value
    None => {
      let value = @async.now()
      perf_detail_started.val = Some(value)
      value
    }
  }
  perf_detail_events.push((name, @async.now() - started))
}

///|
#cfg(any(target="native", target="wasm"))
async fn perf_detail_emit() -> Unit {
  if !perf_detail_is_enabled() || perf_detail_events.is_empty() {
    return
  }
  let fields : Array[String] = []
  for event in perf_detail_events {
    fields.push(
      "{\"stage\":\"" +
      event.0 +
      "\",\"elapsed_ms\":" +
      event.1.to_string() +
      "}",
    )
  }
  let line = "MOONJUST_PERF_DETAIL {\"events\":[" + fields.join(",") + "]}\n"
  try @stdio.stderr.write(@utf8.encode(line)) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}
