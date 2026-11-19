# Unix paths and environment values with invalid UTF-8

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
