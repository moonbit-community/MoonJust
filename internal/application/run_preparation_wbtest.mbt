///|
async test "default-list and fallback read each candidate justfile once" {
  let child = @path.PathValue::new("/workspace/child", Unix)
  let parent = child.parent().unwrap()
  let name = @path.PathValue::new("justfile", Unix)
  let host = @host_testkit.FakeHost::new(
    child,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  host.put_directory(parent)
  host.put_file(
    child.join(name),
    b"set fallback\nset default-list\nlocal:\n  echo local\n",
  )
  host.put_file(
    parent.join(name),
    b"value := 'default'\nrun arg=value:\n  echo {{arg}}\nlast:\n  echo last\n",
  )
  let context = @project.ProjectInput::new(child)
  let list = @cli.parse_arguments([], Map([]))
  guard prepare_run(host, host, host, list, context, default_list=true)
    is Listing(response) else {
    fail("expected the child's default list")
  }
  assert_true(@utf8.decode(response.stdout()).contains("local"))
  assert_eq(host.source_read_count(), 1)
  let args = @cli.parse_arguments(
    ["--dry-run", "run", "explicit", "last"],
    Map([]),
  )
  guard prepare_run(host, host, host, args, context, default_list=true)
    is Ready(plan, _, _) else {
    fail("expected an executable plan after fallback")
  }
  assert_eq(plan.stderr().to_owned(), b"echo explicit\necho last\n")
  assert_eq(host.source_read_count(), 3)
  assert_true(host.process_calls().is_empty())
}
