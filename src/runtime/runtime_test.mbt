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
) -> @executor.ExecutionPlan {
  let compilation = runtime_compilation(text)
  let environment = try! @evaluator.evaluate_compilation(compilation)
  let shell = try! @environment.ShellConfiguration::new("sh", ["-cu"])
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  let cache_directory = runtime_path("/workspace/.moonjust-cache/v1")
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
    options=@executor.ExecutionOptions::new()
      .with_jobs(jobs)
      .with_cache(cache_enabled)
      .with_unstable(true)
      .with_verbosity(verbosity),
    cache_directory~,
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
  let cache_directory = runtime_path("/workspace/.moonjust-cache/v1")
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
async test "missing cache outputs fail without publishing a manifest" {
  let cache_directory = runtime_path("/workspace/.moonjust-cache/v1")
  let plan = runtime_async_plan(
    "[script]\n[cache(outputs=\"artifact\")]\nroot:\n  echo no-artifact\n", 1,
  )
  let host = @host.FakeHost::new(
    runtime_path("/workspace"),
    @host.PlatformInfo::new(Linux, "test", Unix),
  )
  try execute_plan(ProbeProcess::new(), host, host, plan) catch {
    Execution(error=Host(InvalidInput(message)), ..) =>
      assert_true(message.contains("outputs are missing"))
    error => fail("unexpected missing output error: \{Repr(error)}")
  } noraise {
    _ => fail("expected missing cache output failure")
  }
  assert_eq(host.cache_manifest_digests(cache_directory), [])
  assert_eq(host.held_cache_leases(), 0)
}

///|
async test "no-cache bypasses lookup locks and publication" {
  let cache_directory = runtime_path("/workspace/.moonjust-cache/v1")
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
  assert_false(stderr.contains("TOP_SECRET_VERBOSE_CACHE"))
}
