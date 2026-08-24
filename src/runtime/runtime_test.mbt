///|
fn runtime_path(text : String) -> @path.PathValue {
  try! @path.PathValue::new(text, Unix)
}

///|
fn runtime_compilation(text : String) -> @semantic.Compilation {
  let source = @source.Source::from_text(
    @source.SourceId::new(88),
    "justfile",
    text,
  )
  try! @semantic.compile(try! @parser.parse(source))
}

///|
async test "runtime executes steps in order and retains failure output" {
  let compilation = runtime_compilation("build:\n  first\n  second\n")
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let plan = try! @executor.plan_recipe_graph(
    compilation,
    [@executor.RecipeRequest::new("build")],
    environment,
    shell,
    runtime_path("/workspace"),
  )
  for index, command in plan.commands() {
    host.expect_process(
      command.spec(),
      if index == 0 {
        @host.ProcessResult::new(0, b"first\n", b"")
      } else {
        @host.ProcessResult::new(7, b"", b"failed\n")
      },
    )
  }
  try execute_plan(host, host, host, plan) catch {
    Execution(
      error=CommandFailed(exit_code=7, ..),
      stdout~,
      stderr~,
      commands=2
    ) => {
      assert_eq(stdout, b"first\n")
      assert_eq(stderr, b"first\nsecond\nfailed\n")
    }
    error => fail("unexpected runtime error: \{Repr(error)}")
  } noraise {
    _ => fail("expected runtime failure")
  }
}

///|
async test "live runtime emits cross-stream events in execution order" {
  let plan = runtime_async_plan("root:\n  first\n  second\n", 1)
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  for index, step in plan.tasks()[0].steps() {
    guard step is Line(line) else { abort("expected planned line") }
    let (command, _) = try! @executor.materialize_line_async(host, host, line)
    let live = command.spec().copy()
    live.set_inherit_stdin(true)
    live.set_stdout(Inherit)
    live.set_stderr(Inherit)
    host.expect_process(
      live,
      if index == 0 {
        @host.ProcessResult::new(0, b"first-out\n", b"first-err\n")
      } else {
        @host.ProcessResult::new(0, b"second-out\n", b"second-err\n")
      },
    )
  }
  let summary = try! execute_plan_live(host, host, host, host, plan)
  assert_eq(summary.commands(), 2)
  assert_eq(host.output_events(), [
    (Stderr, b"first\n"),
    (Stdout, b"first-out\n"),
    (Stderr, b"first-err\n"),
    (Stderr, b"second\n"),
    (Stdout, b"second-out\n"),
    (Stderr, b"second-err\n"),
  ])
  assert_eq(plan.commands(), [])
}

///|
async test "continue signals are explicit per recipe and preserve subsequent execution" {
  let plan = runtime_async_plan(
    "[continue]\nroot: && cleanup\n  first\ncleanup:\n  cleanup\n", 1,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  for task in plan.tasks() {
    for step in task.steps() {
      guard step is Line(line) else { abort("expected planned line") }
      let (command, _) = try! @executor.materialize_line_async(host, host, line)
      host.expect_process(
        command.spec(),
        if command.recipe() == "root" {
          @host.ProcessResult::from_signal(Interrupt, b"", b"")
        } else {
          @host.ProcessResult::new(0, b"cleanup\n", b"")
        },
      )
    }
  }
  let report = try! execute_plan(host, host, host, plan)
  assert_eq(report.stdout(), b"cleanup\n")
  assert_eq(report.commands(), 2)

  let excluded = runtime_async_plan("[continue('SIGHUP')]\nroot:\n  first\n", 1)
  let rejected = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard excluded.tasks()[0].steps()[0] is Line(line) else {
    abort("expected planned line")
  }
  let (command, _) = try! @executor.materialize_line_async(
    rejected, rejected, line,
  )
  rejected.expect_process(
    command.spec(),
    @host.ProcessResult::from_signal(Interrupt, b"", b""),
  )
  try execute_plan(rejected, rejected, rejected, excluded) catch {
    Execution(error=CommandSignaled(signal=Interrupt, ..), ..) => ()
    error => fail("unexpected excluded signal error: \{Repr(error)}")
  } noraise {
    _ => fail("expected unlisted signal failure")
  }
}

///|
async test "guard failures skip or report according to their exit status" {
  let skipped = runtime_async_plan(
    "set guards\nroot:\n  ?check\n  echo skipped\n",
    1,
    cache_enabled=false,
  )
  let skipped_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  for index, step in skipped.tasks()[0].steps() {
    guard step is Line(line) else { abort("expected guard line") }
    let (command, _) = try! @executor.materialize_line_async(
      skipped_host, skipped_host, line,
    )
    skipped_host.expect_process(
      command.spec(),
      if index == 0 {
        @host.ProcessResult::new(1, b"", b"guard\n")
      } else {
        @host.ProcessResult::new(0, b"", b"unexpected\n")
      },
    )
  }
  let skipped_report = try! execute_plan(
    skipped_host, skipped_host, skipped_host, skipped,
  )
  assert_eq(skipped_report.commands(), 1)

  let rejected = runtime_async_plan(
    "set guards\nroot:\n  ?check\n",
    1,
    cache_enabled=false,
  )
  let rejected_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard rejected.tasks()[0].steps()[0] is Line(line) else {
    abort("expected guard line")
  }
  let (command, _) = try! @executor.materialize_line_async(
    rejected_host, rejected_host, line,
  )
  rejected_host.expect_process(
    command.spec(),
    @host.ProcessResult::new(7, b"", b"bad guard\n"),
  )
  try
    execute_plan(rejected_host, rejected_host, rejected_host, rejected)
  catch {
    Execution(error=GuardCode(code=7, ..), commands=1, ..) => ()
    error => fail("unexpected guard error: \{Repr(error)}")
  } noraise {
    _ => fail("expected guard failure")
  }
}

///|
async test "runtime handles empty plans, ignored failures, and elapsed output" {
  let empty = @executor.combine_execution_plans([])
  let empty_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  assert_eq(
    (try! execute_plan(empty_host, empty_host, empty_host, empty)).commands(),
    0,
  )
  assert_eq(
    (try! execute_plan_live(
      empty_host, empty_host, empty_host, empty_host, empty,
    )).commands(),
    0,
  )

  let ignored = runtime_async_plan("root:\n  -false\n", 1, cache_enabled=false)
  let ignored_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard ignored.tasks()[0].steps()[0] is Line(line) else {
    abort("expected ignored line")
  }
  let (ignored_command, _) = try! @executor.materialize_line_async(
    ignored_host, ignored_host, line,
  )
  ignored_host.expect_process(
    ignored_command.spec(),
    @host.ProcessResult::new(7, b"", b"ignored\n"),
  )
  assert_eq(
    (try! execute_plan(ignored_host, ignored_host, ignored_host, ignored)).commands(),
    1,
  )

  let timed = runtime_async_plan(
    "root:\n  echo timed\n",
    1,
    cache_enabled=false,
    time=true,
  )
  let timed_process = ProbeProcess::new()
  let timed_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let timed_report = try! execute_plan(
    timed_process, timed_host, timed_host, timed,
  )
  assert_true(
    (try! @utf8.decode(timed_report.stderr())).contains(
      "---> root completed in",
    ),
  )
}

///|
async test "runtime maps missing process capabilities to shell diagnostics" {
  let compilation = runtime_compilation("root:\n  echo missing\n")
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let plan = try! @executor.plan_recipe_graph(
    compilation,
    [@executor.RecipeRequest::new("root")],
    environment,
    shell,
    runtime_path("/workspace"),
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try execute_plan(host, host, host, plan) catch {
    Execution(
      error=ShellNotFound(recipe="root", shell="sh", ..),
      commands=0,
      ..
    ) => ()
    error => fail("unexpected process error: \{Repr(error)}")
  } noraise {
    _ => fail("expected shell diagnostic")
  }
  try execute_plan_live(host, host, host, host, plan) catch {
    LiveExecution(
      error=ShellNotFound(recipe="root", shell="sh", ..),
      commands=0,
      ..
    ) => ()
    error => fail("unexpected live process error: \{Repr(error)}")
  } noraise {
    _ => fail("expected live shell diagnostic")
  }
}

///|
async test "runtime covers command signal, interruption, and continuation outcomes" {
  let signaled = runtime_async_plan(
    "root:\n  echo signaled\n",
    1,
    cache_enabled=false,
  )
  let signaled_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard signaled.tasks()[0].steps()[0] is Line(line) else {
    abort("expected line")
  }
  let (signaled_command, _) = try! @executor.materialize_line_async(
    signaled_host, signaled_host, line,
  )
  signaled_host.expect_process(
    signaled_command.spec(),
    @host.ProcessResult::from_signal(Terminate, b"partial\n", b"term\n"),
  )
  try
    execute_plan(signaled_host, signaled_host, signaled_host, signaled)
  catch {
    Execution(
      error=CommandSignaled(signal=Terminate, ..),
      commands=1,
      stdout~,
      stderr~
    ) => {
      assert_eq(stdout, b"partial\n")
      assert_eq(stderr, b"echo signaled\nterm\n")
    }
    error => fail("unexpected signaled command: \{Repr(error)}")
  } noraise {
    _ => fail("expected signaled command")
  }

  let interrupted = runtime_async_plan(
    "root:\n  echo interrupted\n",
    1,
    cache_enabled=false,
  )
  let interrupted_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard interrupted.tasks()[0].steps()[0] is Line(line) else {
    abort("expected line")
  }
  let (interrupted_command, _) = try! @executor.materialize_line_async(
    interrupted_host, interrupted_host, line,
  )
  interrupted_host.expect_process(
    interrupted_command.spec(),
    @host.ProcessResult::from_interruption(Interrupt, b"", b"interrupt\n"),
  )
  try
    execute_plan(
      interrupted_host, interrupted_host, interrupted_host, interrupted,
    )
  catch {
    Execution(error=Interrupted(signal=Interrupt), commands=1, ..) => ()
    error => fail("unexpected interrupted command: \{Repr(error)}")
  } noraise {
    _ => fail("expected interrupted command")
  }

  let continued = runtime_async_plan(
    "[continue]\nroot:\n  echo continue\n",
    1,
    cache_enabled=false,
  )
  let continued_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard continued.tasks()[0].steps()[0] is Line(line) else {
    abort("expected line")
  }
  let (continued_command, _) = try! @executor.materialize_line_async(
    continued_host, continued_host, line,
  )
  continued_host.expect_process(
    continued_command.spec(),
    @host.ProcessResult::from_signal(Interrupt, b"", b"continued\n"),
  )
  assert_eq(
    (try! execute_plan(
      continued_host, continued_host, continued_host, continued,
    )).commands(),
    1,
  )
}

///|
async test "runtime covers guard signal and interruption diagnostics" {
  let guard_signaled = runtime_async_plan(
    "set guards\nroot:\n  ?check\n",
    1,
    cache_enabled=false,
  )
  let signaled_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard guard_signaled.tasks()[0].steps()[0] is Line(line) else {
    abort("expected guard line")
  }
  let (command, _) = try! @executor.materialize_line_async(
    signaled_host, signaled_host, line,
  )
  signaled_host.expect_process(
    command.spec(),
    @host.ProcessResult::from_signal(Terminate, b"", b""),
  )
  try
    execute_plan(signaled_host, signaled_host, signaled_host, guard_signaled)
  catch {
    Execution(error=GuardCode(code=143, ..), commands=1, ..) => ()
    error => fail("unexpected guard signal: \{Repr(error)}")
  } noraise {
    _ => fail("expected guard signal")
  }

  let guard_interrupted = runtime_async_plan(
    "set guards\nroot:\n  ?check\n",
    1,
    cache_enabled=false,
  )
  let interrupted_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard guard_interrupted.tasks()[0].steps()[0] is Line(line) else {
    abort("expected guard line")
  }
  let (command, _) = try! @executor.materialize_line_async(
    interrupted_host, interrupted_host, line,
  )
  interrupted_host.expect_process(
    command.spec(),
    @host.ProcessResult::from_interruption(Interrupt, b"", b""),
  )
  try
    execute_plan(
      interrupted_host, interrupted_host, interrupted_host, guard_interrupted,
    )
  catch {
    Execution(error=Interrupted(signal=Interrupt), commands=1, ..) => ()
    error => fail("unexpected guard interruption: \{Repr(error)}")
  } noraise {
    _ => fail("expected guard interruption")
  }
}

///|
async test "captured runtime covers ignored terminations and successful guards" {
  let cases = [
    (
      "root:\n  -false\n",
      @host.ProcessResult::from_signal(Terminate, b"signal\n", b""),
    ),
    (
      "root:\n  -false\n",
      @host.ProcessResult::from_interruption(Interrupt, b"interrupt\n", b""),
    ),
    (
      "set guards\nroot:\n  ?check\n  echo after\n",
      @host.ProcessResult::new(0, b"guard\n", b""),
    ),
  ]
  for index, row in cases {
    let plan = runtime_async_plan(row.0, 1, cache_enabled=false)
    let host = @host.FakeHost::new(
      runtime_path("/workspace"),
      @host.PlatformInfo::new(Linux, "test", Unix),
    )
    for step_index, step in plan.tasks()[0].steps() {
      guard step is Line(line) else { abort("expected planned line") }
      let (command, _) = try! @executor.materialize_line_async(host, host, line)
      host.expect_process(
        command.spec(),
        if step_index == 0 {
          row.1
        } else {
          @host.ProcessResult::new(0, b"after\n", b"")
        },
      )
    }
    let report = try! execute_plan(host, host, host, plan)
    assert_eq(report.commands(), if index == 2 { 2 } else { 1 })
  }
}

///|
async test "runtime short-circuits empty scripts in captured and live modes" {
  let cwd = runtime_path("/workspace")
  let empty_plan = runtime_async_plan(
    "[script]\nroot:\n",
    1,
    cache_enabled=false,
  )
  let empty_host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  assert_eq(
    (try! execute_plan(empty_host, empty_host, empty_host, empty_plan)).commands(),
    0,
  )
  assert_eq(
    (try! execute_plan_live(
      empty_host, empty_host, empty_host, empty_host, empty_plan,
    )).commands(),
    0,
  )
}

///|
async test "live runtime covers failure, ignore, signal, and guard outcomes" {
  let cases = [
    ("root:\n  false\n", @host.ProcessResult::new(7, b"out", b"err"), "failed"),
    ("root:\n  -false\n", @host.ProcessResult::new(7, b"out", b"err"), "ok"),
    (
      "root:\n  false\n",
      @host.ProcessResult::from_signal(Terminate, b"out", b"err"),
      "signaled",
    ),
    (
      "root:\n  -false\n",
      @host.ProcessResult::from_signal(Terminate, b"out", b"err"),
      "ok",
    ),
    (
      "root:\n  false\n",
      @host.ProcessResult::from_interruption(Interrupt, b"out", b"err"),
      "interrupted",
    ),
    (
      "root:\n  -false\n",
      @host.ProcessResult::from_interruption(Interrupt, b"out", b"err"),
      "ok",
    ),
    (
      "set guards\nroot:\n  ?check\n",
      @host.ProcessResult::new(1, b"", b"guard"),
      "ok",
    ),
    (
      "set guards\nroot:\n  ?check\n",
      @host.ProcessResult::new(7, b"", b"guard"),
      "guard",
    ),
    (
      "set guards\nroot:\n  ?check\n",
      @host.ProcessResult::from_signal(Terminate, b"", b"guard"),
      "guard",
    ),
    (
      "set guards\nroot:\n  ?check\n",
      @host.ProcessResult::from_interruption(Interrupt, b"", b"guard"),
      "interrupted",
    ),
    (
      "[continue]\nroot:\n  false\n",
      @host.ProcessResult::from_signal(Interrupt, b"", b"continued"),
      "ok",
    ),
  ]
  for row in cases {
    let plan = runtime_async_plan(row.0, 1, cache_enabled=false)
    let host = @host.FakeHost::new(
      runtime_path("/workspace"),
      @host.PlatformInfo::new(Linux, "test", Unix),
    )
    guard plan.tasks()[0].steps()[0] is Line(line) else {
      abort("expected planned line")
    }
    let (command, _) = try! @executor.materialize_line_async(host, host, line)
    let live = command.spec().copy()
    live.set_inherit_stdin(true)
    live.set_stdout(Inherit)
    live.set_stderr(Inherit)
    host.expect_process(live, row.1)
    try execute_plan_live(host, host, host, host, plan) catch {
      LiveExecution(error=CommandFailed(..), ..) => assert_eq(row.2, "failed")
      LiveExecution(error=CommandSignaled(..), ..) =>
        assert_eq(row.2, "signaled")
      LiveExecution(error=GuardCode(..), ..) => assert_eq(row.2, "guard")
      LiveExecution(error=Interrupted(..), ..) =>
        assert_eq(row.2, "interrupted")
      error => fail("unexpected live matrix error: \{Repr(error)}")
    } noraise {
      summary => {
        assert_eq(row.2, "ok")
        assert_eq(summary.commands(), 1)
      }
    }
  }
}

///|
async test "runtime cleans a materialized script after success" {
  let compilation = runtime_compilation(
    "[script]\nbuild:\n  #!/bin/sh\n  echo ok\n",
  )
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-eu"])
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let plan = try! @executor.plan_recipe_graph_async(
    host,
    host,
    compilation,
    [@executor.RecipeRequest::new("build")],
    environment,
    @evaluator.EvaluationContext::new(cwd=runtime_path("/workspace")),
    shell,
    runtime_path("/workspace"),
    @executor.ScriptConfiguration::new(
      shell,
      runtime_path("/tmp"),
      @host.PlatformInfo::new(Linux, "test", Unix),
    ),
  )
  let script = match plan.steps()[0] {
    Script(value, _) => value
    _ => abort("expected script step")
  }
  let builder = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let expected = try! @executor.materialize_script(builder, script)
  host.expect_process(
    expected.spec(),
    @host.ProcessResult::new(0, b"ok\n", b""),
  )
  let report = try! execute_plan(host, host, host, plan)
  assert_eq(report.stdout(), b"ok\n")
  assert_eq(host.pending_process_expectations(), 0)
}

///|
async test "live runtime preserves guard short-circuit and cache hit output" {
  let guarded = runtime_async_plan(
    "set guards\nroot:\n  ?check\n  echo skipped\n",
    1,
    cache_enabled=false,
  )
  let guarded_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  for index, step in guarded.tasks()[0].steps() {
    guard step is Line(line) else { abort("expected guard line") }
    let (command, echo) = try! @executor.materialize_line_async(
      guarded_host, guarded_host, line,
    )
    let live = command.spec().copy()
    live.set_inherit_stdin(true)
    live.set_stdout(Inherit)
    live.set_stderr(Inherit)
    guarded_host.expect_process(
      live,
      if index == 0 {
        @host.ProcessResult::new(1, b"", b"")
      } else {
        @host.ProcessResult::new(0, b"", b"")
      },
    )
    ignore(echo)
  }
  let summary = try! execute_plan_live(
    guarded_host, guarded_host, guarded_host, guarded_host, guarded,
  )
  assert_eq(summary.commands(), 1)

  let cached = runtime_async_plan(
    "[script]\n[cache]\nroot:\n  echo cached\n", 1,
  )
  let cached_host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard cached.tasks()[0].steps()[0] is Script(_, echo) else {
    abort("expected cached script")
  }
  let first = try! execute_plan_live(
    ProbeProcess::new(),
    cached_host,
    cached_host,
    cached_host,
    cached,
  )
  assert_eq(first.commands(), 1)
  let second = try! execute_plan_live(
    ProbeProcess::new(),
    cached_host,
    cached_host,
    cached_host,
    cached,
  )
  assert_eq(second.commands(), 0)
  ignore(echo)
}

///|
async test "runtime cache state machine covers keying, miss, hit, and outputs" {
  let plan = runtime_async_plan(
    "[script]\n[cache(inputs='input', outputs='output', extra='tag')]\n" +
    "root:\n  echo cached\n",
    1,
    verbosity=2,
  )
  let task = plan.tasks()[0]
  guard task.cache() is Some(directive) else {
    abort("expected cache directive")
  }
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let input = runtime_path("/workspace/input")
  let output = runtime_path("/workspace/output")
  host.put_file(input, b"cache-input")
  host.put_file(output, b"cache-output")
  assert_true(directive.inputs().contains("input"))
  assert_true(directive.outputs().contains("output"))

  let miss_process = ProbeProcess::new()
  let first = try! execute_plan(miss_process, host, host, plan)
  assert_eq(first.commands(), 1)
  assert_eq(host.held_cache_leases(), 0)
  assert_true(
    host.cache_manifest_digests(plan.cache_directory().unwrap()).length() >= 1,
  )

  let hit_process = ProbeProcess::new()
  let second = try! execute_plan(hit_process, host, host, plan)
  assert_eq(second.commands(), 0)
  assert_true(hit_process.starts.is_empty())

  let live_process = ProbeProcess::new()
  let live_output = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  live_output.put_file(input, b"cache-input")
  live_output.put_file(output, b"cache-output")
  let live = try! execute_plan_live(
    live_process, live_output, live_output, live_output, plan,
  )
  assert_eq(live.commands(), 1)
  let live_hit = try! execute_plan_live(
    ProbeProcess::new(),
    live_output,
    live_output,
    live_output,
    plan,
  )
  assert_eq(live_hit.commands(), 0)
}

///|
async test "runtime cache rejects missing inputs in captured and live execution" {
  let plan = runtime_async_plan(
    "[script]\n[cache(inputs='missing')]\nroot:\n  echo cached\n", 1,
  )
  let captured = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try execute_plan(ProbeProcess::new(), captured, captured, plan) catch {
    Execution(error=CacheFailure(message~), commands=0, ..) =>
      assert_true(message.contains("input does not exist"))
    error => fail("unexpected missing input error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing cache input")
  }
  assert_eq(captured.held_cache_leases(), 0)

  let live = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try execute_plan_live(ProbeProcess::new(), live, live, live, plan) catch {
    LiveExecution(error=CacheFailure(message~), commands=0, ..) =>
      assert_true(message.contains("input does not exist"))
    error => fail("unexpected live missing input error: \{Repr(error)}")
  } noraise {
    _ => fail("expected live missing cache input")
  }
  assert_eq(live.held_cache_leases(), 0)
}

///|
async test "runtime rejects non-positive worker counts in captured and live execution" {
  let plan = runtime_async_plan("root:\n  echo root\n", 0, cache_enabled=false)
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try execute_plan(ProbeProcess::new(), host, host, plan) catch {
    Execution(error=Host(InvalidInput(message)), commands=0, ..) =>
      assert_true(message.contains("jobs must be positive"))
    error => fail("unexpected invalid jobs error: \{Repr(error)}")
  } noraise {
    _ => fail("expected invalid jobs error")
  }
  try execute_plan_live(ProbeProcess::new(), host, host, host, plan) catch {
    LiveExecution(error=CacheFailure(message~), commands=0, ..) =>
      assert_true(message.contains("jobs must be positive"))
    error => fail("unexpected live invalid jobs error: \{Repr(error)}")
  } noraise {
    _ => fail("expected live invalid jobs error")
  }
}

///|
priv struct ProbeProcess {
  mut active : Int
  mut peak : Int
  starts : Array[String]
  failures : Map[String, Int]
  delays : Map[String, Int]
  mut default_delay : Int
}

///|
fn ProbeProcess::new() -> ProbeProcess {
  {
    active: 0,
    peak: 0,
    starts: [],
    failures: Map([]),
    delays: Map([]),
    default_delay: 10,
  }
}

///|
fn ProbeProcess::set_default_delay(self : ProbeProcess, delay : Int) -> Unit {
  self.default_delay = delay
}

///|
fn ProbeProcess::fail(
  self : ProbeProcess,
  command : String,
  exit_code : Int,
  delay : Int,
) -> Unit {
  self.failures[command] = exit_code
  self.delays[command] = delay
}

///|
impl @host.HostAsyncProcess for ProbeProcess with fn run_process_async(
  self : ProbeProcess,
  command : @host.CommandSpec,
) -> @host.ProcessResult raise @host.HostError {
  let name = command.arguments().last().unwrap_or("")
  self.starts.push(name)
  self.active += 1
  self.peak = Int::max(self.peak, self.active)
  defer {
    self.active -= 1
  }
  @async.sleep(self.delays.get(name).unwrap_or(self.default_delay)) catch {
    _ => raise InvalidInput("probe process cancelled")
  }
  @host.ProcessResult::new(self.failures.get(name).unwrap_or(0), b"", b"")
}

///|
async fn runtime_async_plan(
  text : String,
  jobs : Int,
  cache_enabled? : Bool = true,
  verbosity? : Int = 0,
  explain? : Bool = false,
  time? : Bool = false,
  dry_run? : Bool = false,
) -> @executor.ExecutionPlan {
  let compilation = runtime_compilation(text)
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let cache_directory = runtime_path("/workspace/.justcache")
  try! @executor.plan_recipe_graph_async(
    host,
    host,
    compilation,
    [@executor.RecipeRequest::new("root")],
    environment,
    @evaluator.EvaluationContext::new(cwd=runtime_path("/workspace")),
    shell,
    runtime_path("/workspace"),
    @executor.ScriptConfiguration::new(
      shell,
      runtime_path("/tmp"),
      @host.PlatformInfo::new(Linux, "test", Unix),
    ),
    options=@executor.ExecutionOptions::new(time~, dry_run~)
      .with_jobs(jobs)
      .with_cache(cache_enabled)
      .with_unstable(true)
      .with_explain(explain)
      .with_verbosity(verbosity),
    cache_directory~,
  )
}

///|
async test "live runtime short-circuits dry empty tasks and rejects zero jobs" {
  let dry = runtime_async_plan(
    "[doc('Root')]\nroot: first second\nfirst:\nsecond:\n",
    2,
    explain=true,
    dry_run=true,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  assert_eq((try! execute_plan_live(host, host, host, host, dry)).commands(), 0)
  assert_true(host.output_events().any(fn(event) { event.1.length() > 0 }))

  let invalid = runtime_async_plan("root:\n  echo invalid\n", 0)
  try execute_plan(host, host, host, invalid) catch {
    Execution(error=Host(InvalidInput(message)), ..) =>
      assert_true(message.contains("jobs"))
    error => fail("unexpected captured zero-jobs error: \{Repr(error)}")
  } noraise {
    _ => fail("expected captured zero-jobs rejection")
  }
  try execute_plan_live(host, host, host, host, invalid) catch {
    LiveExecution(error=CacheFailure(message~), ..) =>
      assert_true(message.contains("jobs"))
    error => fail("unexpected live zero-jobs error: \{Repr(error)}")
  } noraise {
    _ => fail("expected live zero-jobs rejection")
  }
}

///|
priv enum RuntimeCoverageOutputMode {
  Full
  ShortStdout
  ShortStderr
}

///|
priv struct RuntimeCoverageOutput {
  mode : RuntimeCoverageOutputMode
}

///|
impl @host.HostAsyncOutput for RuntimeCoverageOutput with fn write_output(
  self : RuntimeCoverageOutput,
  stream : @host.OutputStream,
  bytes : Bytes,
) -> Int {
  match self.mode {
    Full => bytes.length()
    ShortStdout =>
      if stream == Stdout {
        Int::max(0, bytes.length() - 1)
      } else {
        bytes.length()
      }
    ShortStderr =>
      if stream == Stderr {
        Int::max(0, bytes.length() - 1)
      } else {
        bytes.length()
      }
  }
}

///|
async test "live runtime rejects incomplete echo and captured stream forwarding" {
  let cwd = runtime_path("/workspace")
  let echo_plan = runtime_async_plan(
    "root:\n  echo output\n",
    1,
    cache_enabled=false,
  )
  let echo_host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try
    execute_plan_live(
      echo_host,
      RuntimeCoverageOutput::{ mode: ShortStderr },
      echo_host,
      echo_host,
      echo_plan,
    )
  catch {
    LiveExecution(error=Host(InvalidInput(message)), commands=0, ..) =>
      assert_true(message.contains("incomplete"))
    error => fail("unexpected echo forwarding error: \{Repr(error)}")
  } noraise {
    _ => fail("expected echo forwarding failure")
  }

  let quiet_plan = runtime_async_plan(
    "root:\n  @echo output\n",
    1,
    cache_enabled=false,
  )
  let stdout_host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard quiet_plan.tasks()[0].steps()[0] is Line(line) else {
    abort("expected quiet line")
  }
  let (command, _) = try! @executor.materialize_line_async(
    stdout_host, stdout_host, line,
  )
  let live = command.spec().copy()
  live.set_inherit_stdin(true)
  live.set_stdout(Inherit)
  live.set_stderr(Inherit)
  stdout_host.expect_process(
    live,
    @host.ProcessResult::new(0, b"stdout", b"stderr"),
  )
  try
    execute_plan_live(
      stdout_host,
      RuntimeCoverageOutput::{ mode: ShortStdout },
      stdout_host,
      stdout_host,
      quiet_plan,
    )
  catch {
    LiveExecution(error=Host(InvalidInput(message)), commands=1, ..) =>
      assert_true(message.contains("incomplete"))
    error => fail("unexpected stdout forwarding error: \{Repr(error)}")
  } noraise {
    _ => fail("expected stdout forwarding failure")
  }

  let stderr_host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  stderr_host.expect_process(live, @host.ProcessResult::new(0, b"", b"stderr"))
  try
    execute_plan_live(
      stderr_host,
      RuntimeCoverageOutput::{ mode: ShortStderr },
      stderr_host,
      stderr_host,
      quiet_plan,
    )
  catch {
    LiveExecution(error=Host(InvalidInput(message)), commands=1, ..) =>
      assert_true(message.contains("incomplete"))
    error => fail("unexpected stderr forwarding error: \{Repr(error)}")
  } noraise {
    _ => fail("expected stderr forwarding failure")
  }
}

///|
async test "live runtime covers timing successful guards and verbose tasks" {
  let cwd = runtime_path("/workspace")
  let timed = runtime_async_plan(
    "root:\n  @echo timed\n",
    1,
    cache_enabled=false,
    time=true,
  )
  let timed_host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard timed.tasks()[0].steps()[0] is Line(line) else {
    abort("expected timed line")
  }
  let (command, _) = try! @executor.materialize_line_async(
    timed_host, timed_host, line,
  )
  let live = command.spec().copy()
  live.set_inherit_stdin(true)
  live.set_stdout(Inherit)
  live.set_stderr(Inherit)
  timed_host.expect_process(live, @host.ProcessResult::new(0, b"", b""))
  assert_eq(
    (try! execute_plan_live(
      timed_host,
      RuntimeCoverageOutput::{ mode: Full },
      timed_host,
      timed_host,
      timed,
    )).commands(),
    1,
  )

  let guarded = runtime_async_plan(
    "set guards\nroot:\n  ?check\n",
    1,
    cache_enabled=false,
  )
  let guarded_host = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  guard guarded.tasks()[0].steps()[0] is Line(line) else {
    abort("expected guard line")
  }
  let (command, _) = try! @executor.materialize_line_async(
    guarded_host, guarded_host, line,
  )
  let live = command.spec().copy()
  live.set_inherit_stdin(true)
  live.set_stdout(Inherit)
  live.set_stderr(Inherit)
  guarded_host.expect_process(live, @host.ProcessResult::new(0, b"", b""))
  assert_eq(
    (try! execute_plan_live(
      guarded_host,
      RuntimeCoverageOutput::{ mode: Full },
      guarded_host,
      guarded_host,
      guarded,
    )).commands(),
    1,
  )

  let verbose = runtime_async_plan(
    "root:\n  echo verbose\n",
    1,
    cache_enabled=false,
    verbosity=1,
  )
  let verbose_report = try! execute_plan(
    ProbeProcess::new(),
    guarded_host,
    guarded_host,
    verbose,
  )
  assert_true(
    (try! @utf8.decode(verbose_report.stderr())).contains("running recipe"),
  )
}

///|
async test "runtime cache propagates filesystem capability failures" {
  let plan = runtime_async_plan(
    "[script]\n[cache(inputs='input')]\nroot:\n  echo cached\n", 1,
  )
  let captured = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  captured.deny(FsRead)
  try execute_plan(ProbeProcess::new(), captured, captured, plan) catch {
    Execution(error=Host(CapabilityDenied(FsRead)), commands=0, ..) => ()
    error => fail("unexpected captured cache host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected captured cache host error")
  }

  let live = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  live.deny(FsRead)
  try execute_plan_live(ProbeProcess::new(), live, live, live, plan) catch {
    LiveExecution(error=Host(CapabilityDenied(FsRead)), commands=0, ..) => ()
    error => fail("unexpected live cache host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected live cache host error")
  }
}

///|
async test "runtime maps line and script host failures in captured and live modes" {
  let cwd = runtime_path("/workspace")
  let platform = @host.PlatformInfo::new(Linux, "test", Unix)
  let line_plan = runtime_async_plan(
    "root:\n  echo line\n",
    1,
    cache_enabled=false,
  )
  let captured_line = @host.FakeHost::new(cwd, platform)
  captured_line.deny(Process)
  try
    execute_plan(captured_line, captured_line, captured_line, line_plan)
  catch {
    Execution(error=Host(CapabilityDenied(Process)), commands=0, ..) => ()
    error => fail("unexpected captured line host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected captured line host error")
  }
  let live_line = @host.FakeHost::new(cwd, platform)
  live_line.deny(Process)
  try
    execute_plan_live(live_line, live_line, live_line, live_line, line_plan)
  catch {
    LiveExecution(error=ShellNotFound(detail~, ..), commands=0, ..) =>
      assert_true(detail.contains("Process"))
    error => fail("unexpected live line host error: \{Repr(error)}")
  } noraise {
    _ => fail("expected live line host error")
  }

  let script_plan = runtime_async_plan(
    "[script]\nroot:\n  echo script\n",
    1,
    cache_enabled=false,
  )
  let captured_create = @host.FakeHost::new(cwd, platform)
  captured_create.deny(FsWrite)
  try
    execute_plan(captured_create, captured_create, captured_create, script_plan)
  catch {
    Execution(error=Host(CapabilityDenied(FsWrite)), commands=0, ..) => ()
    error => fail("unexpected captured script creation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected captured script creation error")
  }
  let live_create = @host.FakeHost::new(cwd, platform)
  live_create.deny(FsWrite)
  try
    execute_plan_live(
      live_create, live_create, live_create, live_create, script_plan,
    )
  catch {
    LiveExecution(error=Host(CapabilityDenied(FsWrite)), commands=0, ..) => ()
    error => fail("unexpected live script creation error: \{Repr(error)}")
  } noraise {
    _ => fail("expected live script creation error")
  }

  let captured_process = @host.FakeHost::new(cwd, platform)
  try
    execute_plan(
      captured_process, captured_process, captured_process, script_plan,
    )
  catch {
    Execution(error=Host(UnexpectedProcess(_)), commands=0, ..) => ()
    error => fail("unexpected captured script process error: \{Repr(error)}")
  } noraise {
    _ => fail("expected captured script process error")
  }
  let live_process = @host.FakeHost::new(cwd, platform)
  try
    execute_plan_live(
      live_process, live_process, live_process, live_process, script_plan,
    )
  catch {
    LiveExecution(error=Host(UnexpectedProcess(_)), commands=0, ..) => ()
    error => fail("unexpected live script process error: \{Repr(error)}")
  } noraise {
    _ => fail("expected live script process error")
  }
}

///|
async test "explanations follow dependency task order" {
  let plan = runtime_async_plan(
    "# Root documentation\nroot: dependency\n  root\n\n" +
    "# Dependency documentation\ndependency:\n  dependency\n",
    1,
    explain=true,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let report = try! execute_plan(ProbeProcess::new(), host, host, plan)
  assert_eq(
    report.stderr(),
    b"#### Dependency documentation\ndependency\n#### Root documentation\nroot\n",
  )
}

///|
async test "parallel dependencies use bounded stable concurrency" {
  let plan = runtime_async_plan(
    "[parallel]\nroot: a b c\n  root\na:\n  a\nb:\n  b\nc:\n  c\n", 2,
  )
  assert_eq(plan.tasks().length(), 4)
  assert_eq(plan.tasks()[0].dependencies(), [])
  assert_eq(plan.tasks()[1].dependencies(), [])
  assert_eq(plan.tasks()[2].dependencies(), [])
  assert_eq(plan.tasks()[3].dependencies(), [0, 1, 2])
  let process = ProbeProcess::new()
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let report = try! execute_plan(process, host, host, plan)
  assert_eq(process.peak, 2)
  assert_eq(process.starts, ["a", "b", "c", "root"])
  assert_eq(report.stderr(), b"a\nb\nc\nroot\n")
}

///|
async test "ordinary dependencies retain serial fences with multiple jobs" {
  let plan = runtime_async_plan("root: a b\na:\n  a\nb:\n  b\n", 4)
  assert_eq(plan.tasks()[1].dependencies(), [0])
  let process = ProbeProcess::new()
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  ignore(try! execute_plan(process, host, host, plan))
  assert_eq(process.peak, 1)
  assert_eq(process.starts, ["a", "b"])
}

///|
async test "parallel failure selection ignores completion timing" {
  let plan = runtime_async_plan(
    "[parallel]\nroot: first second\nfirst:\n  first\nsecond:\n  second\n", 2,
  )
  let process = ProbeProcess::new()
  process.fail("first", 7, 20)
  process.fail("second", 8, 1)
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try execute_plan(process, host, host, plan) catch {
    Execution(error=CommandFailed(recipe="first", exit_code=7, ..), ..) => ()
    error => fail("unexpected deterministic failure: \{Repr(error)}")
  } noraise {
    _ => fail("expected parallel failure")
  }
}

///|
async test "live runtime marks failed dependency consumers blocked" {
  let plan = runtime_async_plan(
    "root: child\n  root\nchild:\n  child\n",
    1,
    cache_enabled=false,
  )
  let process = ProbeProcess::new()
  process.fail("child", 7, 0)
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try execute_plan_live(process, host, host, host, plan) catch {
    LiveExecution(error=CommandFailed(recipe="child", exit_code=7, ..), ..) =>
      ()
    error => fail("unexpected blocked dependency failure: \{Repr(error)}")
  } noraise {
    _ => fail("expected dependency failure")
  }
  assert_eq(process.starts, ["child"])
}

///|
async test "parallel subsequent dependencies join before completion" {
  let plan = runtime_async_plan(
    "[parallel]\nroot: && first second\n  root\nfirst:\n  first\nsecond:\n  second\n",
    2,
  )
  assert_eq(plan.tasks().length(), 4)
  assert_eq(plan.tasks()[0].dependencies(), [])
  assert_eq(plan.tasks()[1].dependencies(), [0])
  assert_eq(plan.tasks()[2].dependencies(), [0])
  assert_eq(plan.tasks()[3].dependencies(), [1, 2])
  let process = ProbeProcess::new()
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let report = try! execute_plan(process, host, host, plan)
  assert_eq(process.peak, 2)
  assert_eq(process.starts, ["root", "first", "second"])
  assert_eq(report.stderr(), b"root\nfirst\nsecond\n")
}

///|
async test "cache miss hit input invalidation and corruption recovery" {
  let cache_directory = runtime_path("/workspace/.justcache")
  let plan = runtime_async_plan(
    "[script]\n[cache(inputs=\"input\")]\nroot:\n  echo cached\n", 1,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  @host.HostFs::write_file(host, runtime_path("/workspace/input"), b"one")
  let first = ProbeProcess::new()
  let first_report = try! execute_plan(first, host, host, plan)
  assert_eq(first_report.commands(), 1)
  assert_eq(first.starts.length(), 1)
  assert_eq(host.held_cache_leases(), 0)
  let first_digests = host.cache_manifest_digests(cache_directory)
  assert_eq(first_digests.length(), 1)

  let hit = ProbeProcess::new()
  let hit_report = try! execute_plan(hit, host, host, plan)
  assert_eq(hit_report.commands(), 0)
  assert_eq(hit.starts, [])
  assert_eq(host.held_cache_leases(), 0)

  @host.HostFs::write_file(host, runtime_path("/workspace/input"), b"two")
  let invalidated = ProbeProcess::new()
  assert_eq((try! execute_plan(invalidated, host, host, plan)).commands(), 1)
  assert_eq(host.cache_manifest_digests(cache_directory).length(), 2)

  let mut current = ""
  for digest in host.cache_manifest_digests(cache_directory) {
    if digest != first_digests[0] {
      current = digest
    }
  }
  assert_true(!current.is_empty())
  host.seed_cache_manifest(cache_directory, current, b"{")
  let recovered = ProbeProcess::new()
  assert_eq((try! execute_plan(recovered, host, host, plan)).commands(), 1)
  let repaired = host.cache_manifest(cache_directory, current).unwrap()
  ignore(try! @cache.decode_manifest(try! @utf8.decode(repaired)))
  assert_eq(host.held_cache_leases(), 0)
}

///|
async test "runtime rejects cached plans without a cache directory" {
  let cwd = runtime_path("/workspace")
  let compilation = runtime_compilation(
    "[script]\n[cache]\nroot:\n  echo cached\n",
  )
  let global = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let planner = @host.FakeHost::new(
    cwd,
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let plan = try! @executor.plan_recipe_graph_async(
    planner,
    planner,
    compilation,
    [@executor.RecipeRequest::new("root")],
    global,
    @evaluator.EvaluationContext::new(cwd~),
    shell,
    cwd,
    @executor.ScriptConfiguration::new(
      shell,
      runtime_path("/tmp"),
      @host.PlatformInfo::new(Linux, "test", Unix),
    ),
    options=@executor.ExecutionOptions::new().with_unstable(true),
  )
  assert_true(plan.tasks()[0].cache() is Some(_))
  assert_eq(plan.cache_directory(), None)
  for live in [false, true] {
    let host = @host.FakeHost::new(
      cwd,
      @host.PlatformInfo::new(Linux, "test", Unix),
    )
    if live {
      try execute_plan_live(host, host, host, host, plan) catch {
        LiveExecution(error=CacheFailure(message~), commands=0, ..) =>
          assert_true(message.contains("cache directory"))
        error => fail("unexpected live cache plan error: \{Repr(error)}")
      } noraise {
        _ => fail("expected live cache plan rejection")
      }
    } else {
      try execute_plan(host, host, host, plan) catch {
        Execution(error=Host(InvalidInput(message)), commands=0, ..) =>
          assert_true(message.contains("cache directory"))
        error => fail("unexpected captured cache plan error: \{Repr(error)}")
      } noraise {
        _ => fail("expected captured cache plan rejection")
      }
    }
    assert_eq(host.process_calls(), [])
  }
}

///|
async test "runtime repairs non UTF-8 cache manifests in captured and live modes" {
  let cache_directory = runtime_path("/workspace/.justcache")
  let plan = runtime_async_plan("[script]\n[cache]\nroot:\n  echo cached\n", 1)
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  ignore(try! execute_plan(ProbeProcess::new(), host, host, plan))
  let digests = host.cache_manifest_digests(cache_directory)
  assert_eq(digests.length(), 1)
  host.seed_cache_manifest(
    cache_directory,
    digests[0],
    Bytes::from_array([0xff]),
  )
  assert_eq(
    (try! execute_plan(ProbeProcess::new(), host, host, plan)).commands(),
    1,
  )
  host.seed_cache_manifest(
    cache_directory,
    digests[0],
    Bytes::from_array([0xff]),
  )
  assert_eq(
    (try! execute_plan_live(ProbeProcess::new(), host, host, host, plan)).commands(),
    1,
  )
  let repaired = host.cache_manifest(cache_directory, digests[0]).unwrap()
  ignore(try! @cache.decode_manifest(try! @utf8.decode(repaired)))
  assert_eq(host.held_cache_leases(), 0)
}

///|
async test "live runtime emits explanation preambles in dependency order" {
  let plan = runtime_async_plan(
    "# Root documentation\nroot: dependency\n  root\n\n" +
    "# Dependency documentation\ndependency:\n  dependency\n",
    1,
    verbosity=1,
    explain=true,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let summary = try! execute_plan_live(
    ProbeProcess::new(),
    host,
    host,
    host,
    plan,
  )
  assert_eq(summary.commands(), 2)
  let stderr = Buffer()
  for event in host.output_events() {
    if event.0 == Stderr {
      stderr.write_bytes(event.1)
    }
  }
  let rendered = try! @utf8.decode(stderr.to_bytes())
  assert_true(rendered.contains("#### Dependency documentation"))
  assert_true(rendered.contains("#### Root documentation"))
  assert_true(rendered.contains("===> running recipe `dependency`"))
  assert_true(rendered.has_prefix("===> running recipe `dependency`"))
}

///|
async test "missing cache outputs leave an empty miss entry" {
  let cache_directory = runtime_path("/workspace/.justcache")
  let plan = runtime_async_plan(
    "[script]\n[cache(outputs=\"artifact\")]\nroot:\n  echo no-artifact\n", 1,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try execute_plan(ProbeProcess::new(), host, host, plan) catch {
    Execution(error=CacheFailure(message~), ..) =>
      assert_true(message.contains("failed to create cache output"))
    error => fail("unexpected missing output error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing cache output failure")
  }
  let digests = host.cache_manifest_digests(cache_directory)
  assert_eq(digests.length(), 1)
  assert_eq(host.cache_manifest(cache_directory, digests[0]), Some(b""))
  assert_eq(host.held_cache_leases(), 0)
}

///|
async test "no-cache bypasses lookup locks and publication" {
  let cache_directory = runtime_path("/workspace/.justcache")
  let plan = runtime_async_plan(
    "[script]\n[cache]\nroot:\n  echo uncached\n",
    1,
    cache_enabled=false,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let process = ProbeProcess::new()
  assert_eq((try! execute_plan(process, host, host, plan)).commands(), 1)
  assert_eq(host.cache_manifest_digests(cache_directory), [])
  assert_eq(host.held_cache_leases(), 0)
}

///|
async test "cancellation releases process script and cache resources" {
  let plan = runtime_async_plan(
    "[script]\n[cache]\nroot:\n  echo long-running\n", 1,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let process = ProbeProcess::new()
  process.set_default_delay(1000)
  @async.with_task_group() <| group => {
    let task = group.spawn(allow_failure=true, () => {
      ignore(execute_plan(process, host, host, plan))
    })
    @async.sleep(20)
    assert_eq(process.active, 1)
    assert_eq(host.held_cache_leases(), 1)
    assert_eq(host.script_temp_creations().length(), 1)
    task.cancel()
    try task.wait() catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
  assert_eq(process.active, 0)
  assert_eq(host.held_cache_leases(), 0)
  let temporary = host.script_temp_creations()[0].0
  assert_false(try! @host.HostFs::file_exists(host, temporary))
}

///|
async test "verbose cache diagnostics report stable hits and key material" {
  let plan = runtime_async_plan(
    "export TOKEN := \"TOP_SECRET_VERBOSE_CACHE\"\n[script]\n[cache]\nroot:\n  echo {{TOKEN}}\n",
    1,
    verbosity=2,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  ignore(try! execute_plan(ProbeProcess::new(), host, host, plan))
  let hit = try! execute_plan(ProbeProcess::new(), host, host, plan)
  let stderr = try! @utf8.decode(hit.stderr())
  assert_true(stderr.has_prefix("===> running recipe `root`...\n"))
  assert_true(stderr.contains("===> cache key "))
  assert_true(stderr.contains("\"working_directory\": "))
  assert_true(stderr.has_suffix("===> cache hit, skipping invocation\n"))
  assert_true(stderr.contains("TOP_SECRET_VERBOSE_CACHE"))
}

///|
async test "contract runtime dependents block on running dependencies" {
  let plan = runtime_async_plan(
    "set quiet\n[parallel]\nroot: b c\n  root\nb: x\n  b\nc: x\n  c\nx:\n  x\n",
    2,
  )
  let process = ProbeProcess::new()
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  ignore(try! execute_plan(process, host, host, plan))
  assert_eq(process.starts, ["x", "b", "c", "root"])
  assert_true(process.peak <= 2)
}

///|
async test "contract runtime jobs limits concurrent recipes" {
  let plan = runtime_async_plan(
    "set quiet\n[parallel]\nroot: a b\n  root\na:\n  a\nb:\n  b\n", 1,
  )
  let process = ProbeProcess::new()
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  ignore(try! execute_plan(process, host, host, plan))
  assert_eq(process.peak, 1)
  assert_eq(process.starts, ["a", "b", "root"])
}

///|
async test "contract runtime prior dependencies run in parallel" {
  let plan = runtime_async_plan(
    "[parallel]\nroot: a b c\n  root\na:\n  a\nb:\n  b\nc:\n  c\n", 2,
  )
  let process = ProbeProcess::new()
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  ignore(try! execute_plan(process, host, host, plan))
  assert_eq(process.starts, ["a", "b", "c", "root"])
  assert_eq(process.peak, 2)
}

///|
async test "contract runtime recipes up to job limit run in parallel" {
  let plan = runtime_async_plan(
    "[parallel]\nroot: a b\n  root\na:\n  a\nb:\n  b\n", 2,
  )
  let process = ProbeProcess::new()
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  ignore(try! execute_plan(process, host, host, plan))
  assert_eq(process.starts, ["a", "b", "root"])
  assert_eq(process.peak, 2)
}
