///|
async test "collect process streams and exit status" {
  let (status, stdout, stderr) = @process.collect_output("/bin/sh", [
    "-c", "printf stdout; printf stderr >&2; exit 7",
  ])
  assert_eq(status, 7)
  assert_eq(stdout.text(), "stdout")
  assert_eq(stderr.text(), "stderr")
}

///|
async test "pass cwd and explicit child environment" {
  @async.with_task_group() <| group => {
    let directory = @fs.tmpdir(prefix="moonjust-host-spike")
    group.add_defer() <| () => {
      @async.protect_from_cancel(() => @fs.rmdir(directory, recursive=true))
    }
    @fs.write_file(
      "\{directory}/input.txt",
      "fixture",
      create_mode=CreateNew,
      permission=0o600,
    )
    let canonical_directory = @fs.realpath(directory)
    let (status, stdout, stderr) = @process.collect_output(
      "/bin/sh",
      ["-c", "printf '%s|%s|' \"$PWD\" \"$MOONJUST_SPIKE\"; cat input.txt"],
      cwd=directory,
      extra_env={ "MOONJUST_SPIKE": "ok" },
    )
    assert_eq(status, 0)
    assert_eq(stdout.text(), "\{canonical_directory}|ok|fixture")
    assert_eq(stderr.text(), "")
  }
}

///|
async test "pipe stdin to child" {
  @async.with_task_group() <| group => {
    let (child_stdin, writer) = @process.write_to_process()
    group.spawn_bg() <| () => {
      defer writer.close()
      writer.write(b"moonjust-stdin")
    }
    let (status, stdout, stderr) = @process.collect_output(
      "/bin/sh",
      ["-c", "cat"],
      stdin=child_stdin,
    )
    assert_eq(status, 0)
    assert_eq(stdout.text(), "moonjust-stdin")
    assert_eq(stderr.text(), "")
  }
}

///|
async test "hard cancellation terminates child" {
  let timed_out = try {
    @async.with_timeout(100, () => {
      @process.run(
        "/bin/sh",
        ["-c", "sleep 10"],
        cancel_handler=@process.hard_cancel(),
      )
      |> ignore
    })
    false
  } catch {
    @async.TimeoutError => true
    _ => false
  }
  assert_true(timed_out)
}
