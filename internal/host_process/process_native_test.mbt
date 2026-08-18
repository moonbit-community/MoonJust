///|
#cfg(not(platform="windows"))
async test "native process adapter maps signal termination" {
  process_test_mutex.acquire()
  defer process_test_mutex.release()
  let signaled = try! @host.CommandSpec::new("/bin/sh", ["-c", "kill -TERM $$"])
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    signaled,
  )
  assert_eq(result.termination(), Signaled(Terminate))
  assert_eq(result.signal().unwrap().exit_code(), 143)
}
