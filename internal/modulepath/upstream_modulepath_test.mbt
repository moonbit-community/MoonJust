///|
test "upstream modulepath::tests::try_from_ok" {
  let root = try! @modulepath.ModulePath::new([])
  assert_true(root.is_root())
  assert_eq(root.components(), [])
  let foo = try! @modulepath.ModulePath::new(["foo"])
  assert_eq(foo.components(), ["foo"])
  assert_eq(foo.as_string(), "foo")
  let foo0 = try! @modulepath.ModulePath::new(["foo0"])
  assert_eq(foo0.as_string(), "foo0")
  let foo_bar = try! @modulepath.ModulePath::new(["foo", "bar"])
  assert_eq(foo_bar.components(), ["foo", "bar"])
  assert_eq(foo_bar.as_string(), "foo::bar")
  assert_eq(try! @modulepath.ModulePath::parse("foo::bar").components(), [
    "foo", "bar",
  ])
}

///|
test "upstream modulepath::tests::try_from_err" {
  for value in [":foo", "foo:", "foo:::bar", "0foo", "f$oo"] {
    let accepted = try @modulepath.ModulePath::parse(value) catch {
      _ => false
    } noraise {
      _ => true
    }
    assert_true(!accepted)
  }
  let accepted = try @modulepath.ModulePath::new([""]) catch {
    _ => false
  } noraise {
    _ => true
  }
  assert_true(!accepted)
}
