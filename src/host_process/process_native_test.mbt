///|
async test "native process adapter maps signal termination" {
  let signaled = try! @host.CommandSpec::new("/bin/sh", ["-c", "kill -TERM $$"])
  let result = try! @host.HostAsyncProcess::run_process_async(
    ProcessAdapter::new(),
    signaled,
  )
  assert_eq(result.termination(), Signaled(Terminate))
}
