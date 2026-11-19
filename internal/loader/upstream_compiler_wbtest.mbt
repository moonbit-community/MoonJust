///|
async test "upstream compiler::tests::find_module_file" {
  for
    (flavor, os, cwd) in [
      (@path.PathFlavor::Unix, @host.OperatingSystem::Linux, "/workspace"),
      (Windows, Windows, "C:/workspace"),
    ] {
    let root = @path.PathValue::new(cwd, flavor)
    fn path(name : String) -> @path.PathValue {
      try! @path.PathValue::new(name, flavor)
    }
    let source = root.join(path("justfile"))
    let span = @source.Span::origin(@source.SourceId::new(966))
    async fn check(
      explicit : String?,
      files : Array[String],
      expected : Result[String?, Array[String]],
    ) -> Unit {
      let host = @host_testkit.FakeHost::new(
        root,
        @host.PlatformInfo::new(os, None, flavor),
      )
      for file in files {
        let candidate = root.join(path(file))
        host.put_directory(candidate.parent().unwrap())
        host.put_file(candidate, b"")
      }
      let literal = explicit.map(s => {
        @syntax.StringLiteral::new(s, s, Raw, span)
      })
      let declaration = @syntax.Module::new("foo", span, literal, false, span)
      match expected {
        Ok(Some(name)) =>
          assert_eq(
            resolve_module_file(host, source, declaration),
            Some(root.join(path(name))),
          )
        Ok(None) => {
          let optional = @syntax.Module::new("foo", span, literal, true, span)
          assert_eq(resolve_module_file(host, source, optional), None)
          try resolve_module_file(host, source, declaration) catch {
            ModuleFileMissing(module_name="foo", ..) => ()
            error => fail("unexpected module lookup error: \{Repr(error)}")
          } noraise {
            _ => fail("unexpected module match: \{Repr(files)}")
          }
        }
        Err(names) =>
          try resolve_module_file(host, source, declaration) catch {
            AmbiguousModuleFile(module_name="foo", found~, ..) =>
              assert_eq(found, names.map(path))
            error => fail("unexpected module lookup error: \{Repr(error)}")
          } noraise {
            _ => fail("expected ambiguous candidates: \{Repr(files)}")
          }
      }
    }
    check(None, ["foo.just"], Ok(Some("foo.just")))
    check(None, ["FOO.just"], Ok(None))
    check(None, ["foo/MOD.just"], Ok(None))
    check(Some("bar"), ["bar"], Ok(Some("bar")))
    for leaf in ["mod.just", "justfile", "JUSTFILE", ".justfile", ".JUSTFILE"] {
      let implicit = "foo/" + leaf
      let explicit = "bar/" + leaf
      check(None, [implicit], Ok(Some(implicit)))
      check(Some("bar"), [explicit], Ok(Some(explicit)))
    }
    check(
      None,
      ["foo/justfile", "foo/.justfile"],
      Err(["foo/.justfile", "foo/justfile"]),
    )
    check(
      Some("bar"),
      ["bar/mod.just", "bar/justfile"],
      Err(["bar/justfile", "bar/mod.just"]),
    )
    check(None, ["foo.just", "foo/mod.just"], Err(["foo/mod.just", "foo.just"]))
  }
}

///|
async test "module discovery reports every matching directory entry even when two resolve to one file" {
  let root = @path.PathValue::new("/workspace", Unix)
  let host = @host_testkit.FakeHost::new(
    root,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  let justfile = root.join(@path.PathValue::new("justfile", Unix))
  let direct = root.join(@path.PathValue::new("foo.just", Unix))
  let directory = root.join(@path.PathValue::new("foo", Unix))
  let nested = directory.join(@path.PathValue::new("mod.just", Unix))
  host.put_file(justfile, b"mod foo\n")
  host.put_file(direct, b"")
  host.put_directory(directory)
  host.put_file(nested, b"")
  host.set_canonical(nested, direct)
  host.put_file(directory.join(@path.PathValue::new(".justfile", Unix)), b"")
  try load_graph(host, justfile, @source.SourceId::new(0)) catch {
    AmbiguousModuleFile(_) as error =>
      assert_eq(
        error.message(),
        "found multiple source files for module `foo`: `foo/.justfile`, `foo/mod.just`, and `foo.just`",
      )
    error => fail("unexpected loader error: \{Repr(error)}")
  } noraise {
    _ => fail("expected three ambiguous entries")
  }
}

///|
async test "loading a directory named foo.just reports the selected source path" {
  let root = @path.PathValue::new("/workspace", Unix)
  let host = @host_testkit.FakeHost::new(
    root,
    @host.PlatformInfo::new(Linux, None, Unix),
  )
  let justfile = root.join(@path.PathValue::new("justfile", Unix))
  let directory = root.join(@path.PathValue::new("foo.just", Unix))
  host.put_file(justfile, b"mod foo\n")
  host.put_directory(directory)
  try load_graph(host, justfile, @source.SourceId::new(0)) catch {
    SourceIsDirectory(path) as error => {
      assert_eq(path, directory)
      assert_eq(
        error.message(),
        "failed to read justfile at `/workspace/foo.just`: Is a directory (os error 21)",
      )
    }
    error => fail("unexpected loader error: \{Repr(error)}")
  } noraise {
    _ => fail("expected directory read error")
  }
}
