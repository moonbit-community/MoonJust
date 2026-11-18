///|
async test "cancelling a process wait terminates and reaps the child" {
  @async.with_timeout(10000, () => {
    @async.with_task_group() <| group => {
      let (input, writer) = @async_process.write_to_process()
      defer writer.close()
      // Keep stdin open so the child cannot exit before it is cancelled.
      let (program, arguments) = if windows_process_runtime() {
        ("cmd.exe", ["/d", "/s", "/c", "set /p value="])
      } else {
        ("sh", ["-c", "read value"])
      }
      let process = @async_process.spawn(
        group,
        program,
        arguments,
        stdin=Shared(input),
        cancel_handler=@async_process.hard_cancel(),
      )
      let started = Ref(false)
      let waiter = group.spawn(() => {
        started.val = true
        wait_for_child(process)
      })
      while !started.val {
        @async.sleep(0)
      }
      waiter.cancel()
      assert_true(waiter.wait() is Cancelled)
      assert_true(process.try_wait() is Some(_))
    }
  })
}

///|
async test "capture drains both full pipes without decoding and preserves the exit status" {
  @async.with_timeout(30000, () => {
    let command = if windows_process_runtime() {
      @host.CommandSpec::new("powershell.exe", [
        "-NoProfile", "-Command", "$m = New-Object IO.MemoryStream; [Console]::OpenStandardInput().CopyTo($m); $m.Position=0; $m.CopyTo([Console]::OpenStandardError()); $m.Position=0; $m.CopyTo([Console]::OpenStandardOutput()); exit 7",
      ])
    } else {
      @host.CommandSpec::new("sh", ["-c", "tee /dev/stderr; exit 7"])
    }
    let payload = FixedArray::makei(256 * 1024, index => (index % 256).to_byte()).unsafe_reinterpret_as_bytes()
    command.set_stdin(payload)
    let result = run_process_with_output_limit(command, payload.length())
    assert_true(result.exit_code() == Some(7))
    assert_true(result.stdout() == payload[:])
    assert_true(result.stderr() == payload[:])
  })
}

///|
async test "observed process wait preserves normal exit status" {
  @async.with_timeout(10000, () => {
    @async.with_task_group() <| group => {
      let (program, arguments) = if windows_process_runtime() {
        ("cmd.exe", ["/d", "/s", "/c", "exit 7"])
      } else {
        ("sh", ["-c", "exit 7"])
      }
      let process = @async_process.spawn(group, program, arguments)
      assert_true(wait_for_child(process) is Completed(7))
    }
  })
}
