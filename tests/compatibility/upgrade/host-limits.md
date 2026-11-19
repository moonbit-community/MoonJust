# Wasm host limits

## Invocation directory

The upstream test `non_unicode::non_unicode_invocation_directory_is_an_error`
starts just inside a directory whose last component ends with the byte `ff`.
On Linux arm64, just 1.59.0 exits 1 and prints the current path with the
invalid byte rendered as U+FFFD. With moonrun 0.1.20261117 (`eb64713`),
the host aborts with status 134 inside `unstable_api/filesystem.rs` while
servicing the guest's current-directory request. This identity is deferred.
[Upstream test](../upstream/just-1.59.0/source/tests/non_unicode.rs)

MoonBit's Wasm `@env.current_dir()` returns `String?`. The host aborts before
the function can return an error to the application. The public async
`realpath` API decodes Unix filenames with replacement and returns a
`String`. A genuine U+FFFD and an invalid byte can consequently produce
the same result. Returning the upstream diagnostic reliably requires a host
API that preserves the bytes or reports invalid Unicode with the display path.

To reproduce on Linux, set `JUST159` and `WASM` to absolute paths to the
official binary and the release Wasm. Run each program in the same directory.

```sh
root=$(mktemp -d)
bad=$(printf 'foo\377')
valid=$(printf 'foo\357\277\275')
mkdir "$root/$bad" "$root/$valid"
printf 'foo:\n echo bar\n' > "$root/$valid/justfile"
(cd "$root/$valid" && "$JUST159")
(cd "$root/$valid" && moonrun "$WASM")
(cd "$root/$bad" && "$JUST159")
(cd "$root/$bad" && moonrun "$WASM")
```

Both programs execute the recipe inside the valid U+FFFD directory.
An unrelated directory entry with invalid bytes also permits normal recipe
discovery and execution. The Linux differential job exercises that case
under its own identity. [Sibling-file fixture](../../differential/cases/upstream-non-unicode-sibling)

## Directory builtins

The upstream `dir_not_unicode` unit test supplies invalid bytes to the
directory lookup helper. To exercise that path through the official CLI on
Linux, create a justfile containing `value := config_directory()` and run the
commands below from its directory.

```sh
XDG_CONFIG_HOME="/tmp/$(printf 'foo\377')" "$JUST159" --evaluate value
XDG_CONFIG_HOME="/tmp/$(printf 'foo\377')" moonrun "$WASM" -- --evaluate value
```

In the Linux arm64 probe, official just exited 1, rendered the invalid byte
as U+FFFD and highlighted the call. MoonJust exited 0 and returned the
default config directory. Both returned `/tmp/safe` for the valid input
`XDG_CONFIG_HOME=/tmp/safe`. The guest environment interface provides
string keys and values. The invalid value was absent from that interface.
The upstream Unix identity is deferred until the host can distinguish an
absent value from a present value containing invalid bytes.
[Upstream directory helper test](../upstream/just-1.59.0/source/src/function.rs#L876)

## Propagating a Windows exit code with the high bit set

On the Windows CI host, a recipe that ran `exit /b -65536` through
`cmd.exe /c` produced the same diagnostic in both CLIs, including
`exit code -65536`. The official process returned -65536. The MoonJust
process returned 1. [Windows run](https://github.com/moonbit-community/MoonJust/actions/runs/44465470018/job/135362403665)

The guest calls the public `@env.exit(Int32)` with the child's exit code.
The linear-memory Wasm backend routes this call through WASI `proc_exit`.
moonrun reads the argument as a `u32` and replaces a value above
`i32::MAX` with 1. A standalone Wasm program calling `@env.exit(-65536)`
also returned 1 on macOS. Fixing propagation requires a change in the
runtime. [moonrun exit conversion](https://github.com/moonbitlang/moon/blob/eb64713/crates/moonrun/src/wasi/mod.rs#L1484-L1489)

The Windows fixture runs both binaries and also verifies the recorded upstream
status and outputs. Only the -65536 to 1 status difference is accepted. An
upstream runtime fix will make this expectation fail and signal that it can be
removed. This supplemental fixture has no ID in the pinned upstream test list.
[Fixture](../../differential/cases/windows-negative-exit-code)
