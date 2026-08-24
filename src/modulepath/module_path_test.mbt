///|
test "module paths normalize root parse child and prefix operations" {
  let root = ModulePath::root()
  assert_true(root.is_root())
  assert_eq(root.as_string(), "")
  let tools = try! ModulePath::parse("tools::release::")
  assert_eq(tools.components(), ["tools", "release"])
  assert_eq(tools.as_string(), "tools::release")
  assert_eq(tools.parent().unwrap().as_string(), "tools")
  assert_eq(root.child("tools").as_string(), "tools")
  assert_true(tools.starts_with(try! ModulePath::parse("tools")))
  assert_false(tools.starts_with(try! ModulePath::parse("other")))
}

///|
test "module paths reject malformed components" {
  for value in [":foo", "foo:", "foo:::bar", "0foo", "f$oo", "foo::::bar"] {
    try ModulePath::parse(value) catch {
      InvalidModulePath(_) => ()
    } noraise {
      _ => fail("expected invalid module path: \{value}")
    }
  }
}
