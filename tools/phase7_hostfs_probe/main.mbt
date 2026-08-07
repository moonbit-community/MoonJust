///|
async fn cleanup(path : @path.PathValue) -> Unit {
  try @async_fs.remove(path.as_string()) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
async fn run_probe() -> Unit raise Error {
  let arguments = @env.args()
  guard arguments.length() == 2 else { abort("expected allow or deny mode") }
  let mode = arguments[1]
  let host = @transaction.PolicyFs::new()
  let directory = @path.PathValue::new("_build", Unix)
  let target = @path.PathValue::new(
    "_build/moonjust-wasm-policy-transaction",
    Unix,
  )
  if mode == "allow" {
    cleanup(target)
    @host.HostAtomicFs::write_file_atomic(host, target, b"new\r\n", true)
    assert_eq(@host.HostFs::read_file(host, target), b"new\r\n")
    try
      @host.HostAtomicFs::write_file_atomic(host, target, b"lost", false)
    catch {
      AlreadyExists(actual) => assert_eq(actual, target)
      error => abort("unexpected no-overwrite result: \{Repr(error)}")
    } noraise {
      _ => abort("no-overwrite transaction unexpectedly succeeded")
    }
    cleanup(target)
    let debris = @host.HostFs::read_dir(host, directory).filter(name => {
      name.has_prefix(".moonjust.tmp.")
    })
    assert_eq(debris, [])
    println("allow: atomic replace, CRLF, no-overwrite, cleanup")
  } else if mode == "deny" {
    try
      @host.HostAtomicFs::write_file_atomic(host, target, b"denied", true)
    catch {
      PermissionDenied(FsWrite, ..) => ()
      error => abort("unexpected policy denial: \{Repr(error)}")
    } noraise {
      _ => abort("read-only policy allowed an atomic write")
    }
    assert_false(@host.HostFs::file_exists(host, target))
    let debris = @host.HostFs::read_dir(host, directory).filter(name => {
      name.has_prefix(".moonjust.tmp.")
    })
    assert_eq(debris, [])
    println("deny: typed write denial, cleanup")
  } else {
    abort("expected allow or deny mode")
  }
}

///|
async fn main {
  try run_probe() catch {
    error => abort("Phase 7 HostFs probe failed: \{Repr(error)}")
  } noraise {
    _ => ()
  }
}
