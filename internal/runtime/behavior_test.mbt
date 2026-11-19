///|
fn runtime_host() -> @host_testkit.FakeHost raise {
  @host_testkit.FakeHost::new(
    @path.PathValue::new("/workspace", Unix),
    @host.PlatformInfo::new(Linux, None, Unix),
  )
}

///|
fn runtime_source(
  text : String,
  allow_unstable~ : Bool = false,
) -> @semantic.Compilation raise {
  let source = @source.Source::from_text(
    @source.SourceId::new(710),
    "justfile",
    text,
  )
  @semantic.compile(@parser.parse(source), allow_unstable~)
}

///|
async fn runtime_graph(
  host : @host_testkit.FakeHost,
  source : String,
  options~ : @planner.ExecutionOptions = @planner.ExecutionOptions::new(),
  cache_directory? : @path.PathValue,
) -> @planner.ExecutionPlan {
  let cwd = host.current_dir()
  let shell = @environment.ShellConfiguration::new("sh", ["-cu"])
  let compilation = runtime_source(source, allow_unstable=options.unstable())
  @planner.plan_recipe_graph_async(
    host,
    host,
    compilation,
    [@planner.RecipeRequest::new("run")],
    @evaluator.evaluate_compilation(compilation),
    @evaluator.EvaluationContext::new(
      cwd~,
      lists=compilation.settings().bool("lists"),
      num_jobs=options.jobs(),
    ),
    shell,
    cwd,
    @planner.ScriptConfiguration::new(shell, cwd, host.platform_info()),
    options~,
    cache_directory?,
  )
}

///|
async test "live execution emits command echoes and both child streams in order" {
  let compilation = runtime_source("build:\n  echo build\n")
  let environment = @evaluator.Environment::new()
  let shell = @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = runtime_host()
  let plan = @planner.plan_recipe_graph(
    compilation,
    [@planner.RecipeRequest::new("build")],
    environment,
    shell,
    host.current_dir(),
  )
  let expected = plan.commands()[0].spec().copy()
  expected.set_inherit_stdin(true)
  expected.set_stdout(Inherit)
  expected.set_stderr(Inherit)
  host.expect_process(
    expected,
    @host.ProcessResult::new(0, b"ok\n", b"detail\n"),
  )
  let summary = @runtime.execute_plan_live(host, host, host, host, plan, (_, _) => {
    ()
  })
  assert_eq(summary.commands(), 1)
  assert_eq(host.pending_process_expectations(), 0)
  assert_eq(host.output_events().to_owned(), [
    (Stderr, b"echo build\n"),
    (Stdout, b"ok\n"),
    (Stderr, b"detail\n"),
  ])
}

///|
priv struct TestProcess(
  async (@host.CommandSpec) -> @host.ProcessResult noraise,
)

///|
async fn expect_timestamped_run(source : String, expected : Bytes) -> Unit {
  let host = runtime_host()
  host.set_clock_millis(37_230_456L)
  let plan = runtime_graph(host, source)
  let process = TestProcess(_ => @host.ProcessResult::new(0, b"foo\n", b""))
  let result = @runtime.execute_plan_live(process, host, host, host, plan, (
    _,
    _,
  ) => ())
  assert_eq(result.commands(), 1)
  assert_eq(host.output_events().to_owned(), [
    (Stderr, expected),
    (Stdout, b"foo\n"),
  ])
}

///|
async test "upstream timestamps::attribute" {
  expect_timestamped_run(
    "[timestamp]\nrun:\n  echo foo\n", b"[10:20:30] echo foo\n",
  )
}

///|
async test "upstream timestamps::attribute_format" {
  expect_timestamped_run(
    "[timestamp('%H:%M:%S%.3f')]\nrun:\n  echo foo\n", b"[10:20:30.456] echo foo\n",
  )
}

///|
async test "upstream timestamps::attribute_format_expression" {
  expect_timestamped_run(
    "format := '%H:%M:%S' + '%.3f'\n[timestamp(format)]\nrun:\n  echo foo\n", b"[10:20:30.456] echo foo\n",
  )
}

///|
async test "upstream timestamps::attribute_script" {
  expect_timestamped_run(
    "[timestamp]\nrun:\n  #!/bin/sh\n  echo foo\n", b"[10:20:30] run\n",
  )
}

///|
impl @host.HostProcess for TestProcess with fn run_process(self, command) -> @host.ProcessResult raise @host.HostError {
  (self.0)(command)
}

///|
async test "parallel dependencies run up to the available jobs" {
  let host = runtime_host()
  let source =
    #|[parallel]
    #|run: a b c
    #|a:
    #|  echo a
    #|b:
    #|  echo b
    #|c:
    #|  echo c
  for (jobs, expected_peak) in [(1, 1), (2, 2), (100, 3)] {
    let plan = runtime_graph(
      host,
      source,
      options=@planner.ExecutionOptions::new().with_jobs(jobs),
    )
    let mut active = 0
    let mut peak = 0
    let process = TestProcess(_ => {
      active += 1
      peak = peak.max(active)
      @async.pause()
      active -= 1
      @host.ProcessResult::new(0, b"", b"")
    })
    let summary = @runtime.execute_plan_live(process, host, host, host, plan, (
      _,
      _,
    ) => ())
    assert_eq(summary.commands(), 3)
    assert_eq(peak, expected_peak)
  }
}

///|
async test "nonpositive jobs fail before any task runs" {
  let host = runtime_host()
  for jobs in [0, -1] {
    let plan = runtime_graph(
      host,
      "run:\n  echo run\n",
      options=@planner.ExecutionOptions::new().with_jobs(jobs),
    )
    try
      @runtime.execute_plan_live(host, host, host, host, plan, (_, _) => ())
    catch {
      error => {
        assert_true(
          error.error()
          is CacheFailure(message="execution plan jobs must be positive"),
        )
        assert_eq(error.commands(), 0)
      }
    } noraise {
      _ => fail("expected invalid jobs to fail")
    }
  }
  assert_true(host.process_calls().is_empty())
  assert_true(host.output_events().is_empty())
}

///|
async test "command timestamps read the clock after the previous command completes" {
  let host = runtime_host()
  let process = TestProcess(_ => {
    host.set_clock_millis(2000L)
    @host.ProcessResult::new(0, b"", b"")
  })
  let plan = runtime_graph(
    host,
    "run:\n  echo one\n  echo two\n",
    options=@planner.ExecutionOptions::new(timestamp="%s"),
  )
  host.set_clock_millis(1000L)
  let summary = @runtime.execute_plan_live(process, host, host, host, plan, (
    _,
    _,
  ) => ())
  assert_eq(summary.commands(), 2)
  assert_eq(host.output_events().to_owned(), [
    (Stderr, b"[1] echo one\n"),
    (Stderr, b"[2] echo two\n"),
  ])
}

///|
async test "a failed dependency forwards child output and blocks its dependent" {
  let host = runtime_host()
  let plan = runtime_graph(
    host,
    (
      #|set unstable
      #|set lists
      #|[no-exit-message]
      #|leaf:
      #|  echo {{num_jobs()}}
      #|run: leaf
      #|  echo blocked
    ),
    options=@planner.ExecutionOptions::new().with_jobs(1000),
  )
  let expected = @host.CommandSpec::new("sh", ["-cu", "echo 1000"])
  expected.set_cwd(host.current_dir())
  expected.set_inherit_environment(false)
  expected.set_inherit_stdin(true)
  expected.set_stdout(Inherit)
  expected.set_stderr(Inherit)
  host.expect_process(
    expected,
    @host.ProcessResult::new(23, b"prefix", b"failure"),
  )
  try
    @runtime.execute_plan_live(host, host, host, host, plan, (_, _) => ())
  catch {
    error => {
      assert_eq(error.exit_code(), 23)
      assert_eq(error.commands(), 1)
      assert_false(error.show_message())
    }
  } noraise {
    _ => fail("expected dependency failure")
  }
  assert_eq(host.process_calls().length(), 1)
  assert_eq(host.output_events().to_owned(), [
    (Stderr, b"echo 1000\n"),
    (Stdout, b"prefix"),
    (Stderr, b"failure"),
  ])
}

///|
async test "a cached script runs again only after its input changes" {
  let host = runtime_host()
  let cwd = host.current_dir()
  let input = cwd.join(@path.PathValue::new("input", Unix))
  host.put_file(input, b"one")
  let process = TestProcess(_ => @host.ProcessResult::new(0, b"cached\n", b""))
  let plan = runtime_graph(
    host,
    "[cache(inputs='input')]\n[script]\nrun:\n  echo cached\n",
    options=@planner.ExecutionOptions::new().with_unstable(true),
    cache_directory=cwd,
  )
  let first = @runtime.execute_plan_live(process, host, host, host, plan, (_, _) => {
    ()
  })
  assert_eq(first.commands(), 1)
  assert_eq(host.cache_manifest_digests(cwd).length(), 1)
  assert_eq(host.held_cache_leases(), 0)
  let second = @runtime.execute_plan_live(host, host, host, host, plan, (_, _) => {
    ()
  })
  assert_eq(second.commands(), 0)
  assert_eq(host.script_temp_creations().length(), 1)
  assert_true(host.process_calls().is_empty())
  assert_eq(host.held_cache_leases(), 0)
  host.put_file(input, b"two")
  let third = @runtime.execute_plan_live(process, host, host, host, plan, (_, _) => {
    ()
  })
  assert_eq(third.commands(), 1)
  assert_eq(host.script_temp_creations().length(), 2)
  assert_eq(host.cache_manifest_digests(cwd).length(), 2)
  assert_eq(host.held_cache_leases(), 0)
}
