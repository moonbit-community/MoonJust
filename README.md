# MoonJust

MoonJust runs justfiles. Its only product is a linear-memory Wasm executable, written in MoonBit, with CLI behavior compared against official **just 1.59.0**. The root package is the executable; there is no public library facade.

## Quick start

~~~sh
moon update
moon run --target wasm . -- --version
moon build --release --target wasm .
moonrun _build/wasm/release/build/MoonJust.wasm -- --list
~~~

For example, save this as `justfile`:

~~~make
build profile="debug":
    echo "building {{profile}}"
~~~

Run `moonrun _build/wasm/release/build/MoonJust.wasm -- build release`. The executable supports project discovery, imports and modules, dotenv, queries, dry runs, recipes, dependencies, scripts, parallel jobs and caching. Filesystem, environment and child-process access depend on the host policy. A justfile is executable code; granting subprocess access is not a sandbox for recipes. See [SECURITY.md](SECURITY.md).

## Wasm capabilities

- Project loading follows real paths. Executable lookup and canonicalization do not spawn helper commands. Windows lookup honors `PATHEXT`.
- `--fmt --check` is read-only. Formatting an already formatted file succeeds without touching it. When an existing file would change, MoonJust refuses before writing because the public Wasm filesystem API does not supply the mode needed for a permission-preserving atomic replacement. Formatting stdin still writes to stdout. `--init` creates a file atomically and never replaces one.
- Invalid UTF-8 bytes in a Linux working directory or a Unix directory environment value can be lost before MoonJust can produce just's diagnostic. [Host reproductions and controls](tests/compatibility/upgrade/host-limits.md)
- On Windows, recipe diagnostics preserve the child's signed exit code. For codes with the high bit set, moonrun returns 1 to the calling process. [Windows exit-code probe](tests/compatibility/upgrade/host-limits.md#propagating-a-windows-exit-code-with-the-high-bit-set)
- The OS comes from the runtime. Where needed, provide `MOONJUST_ARCH`, `MOONJUST_PID`, `MOONJUST_NUM_CPUS` or `MOONJUST_EXECUTABLE` for facts the runtime cannot supply. A recursive recipe needs an executable launcher, not just a path to Wasm bytes. Local time without a known offset is not silently treated as UTC.
- Process cancellation covers the direct child. The compatibility report distinguishes live CLI comparisons, document checks, indexed MoonBit assertions, scoped smoke tests and exclusions. It lists three known formatting refusals and counts the two product-identity checks separately. [Coverage categories](tests/compatibility/README.md#reading-a-coverage-report)

## Verification

~~~sh
moon check --target wasm --deny-warn
moon test --target wasm
moon build --release --target wasm .
moon info && moon fmt
~~~

CI tests the Wasm CLI against official just on Linux, macOS and Windows. Only the test tools are built as Native executables. The differential CI jobs consume the same Wasm artifact; test-injected host facts and re-entry are not standalone product capabilities. Benchmarks are local only. The separate manual MoonX workflow verifies the exact published version on all three hosts; it never publishes.

See the [compatibility runner](tests/compatibility/README.md), [architecture](docs/ARCHITECTURE.md), [maintenance evidence](docs/maintenance/WASM_MIGRATION.md), and [contributor checks](CONTRIBUTING.md). The [published-artifact gate](docs/release/MOONX_RELEASE_GATE.md) is separate from source verification. MoonJust is licensed under Apache-2.0; pinned upstream fixtures retain their [provenance](tests/compatibility/upstream/NOTICE.md). MoonJust is independent of the upstream just project.
