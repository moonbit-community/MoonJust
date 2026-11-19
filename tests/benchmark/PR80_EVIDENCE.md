# Q07–Q09 on the two sides of #80

Measured on 2026-11-19, Darwin 25.5.0 arm64, Apple M4, with Moon and moonrun
`0.1.20261117 (eb64713)`, moonc `0.10.21+06da1ed44`, and identical locked
dependencies. Both release Wasm binaries came from clean source archives.

| Build | Git commit | Release Wasm SHA-256 |
| --- | --- | --- |
| Before (#79) | `97375e5a4d319da904bb924ba40339d161f926c4` | `61ecbc54f77be0906030176f16a56e71790e68699b0d13ac8c5c520ded5b3148` |
| After (#80) | `ab99e56d2c2f5b65b893639eabf9a9877785b331` | `2fa1db91415524dff531a4453f6ff9391b8b91aa1b12ee4bad8ebb130a4e1e3e` |

## Q07. Builtin lookup

The inputs use 16 copies of `trim(uppercase(lowercase(' X ')))` per expression.
For one parsed expression, compiler coverage counted **48 lookups on each
side**, 48 registry builds before and 1 after. The corresponding number of
individual builtin specifications constructed was 3,984 and 83. The warm
benchmark parses once, repeats evaluation in the same process, checks the
result, and keeps it in the timed loop.

| Measurement | Before | After |
| --- | ---: | ---: |
| Fresh CLI, 48 calls, median | 67.646 ms | 57.616 ms |
| Fresh CLI, 768 calls, median | 166.712 ms | 77.668 ms |
| Warm evaluator, 48 calls, mean ± SD | 1.32 ms ± 0.31 ms | 24.45 µs ± 0.42 µs |

The fresh-process measurement includes moonrun startup, loading, parsing and
semantic validation. Filesystem pages may be warm. The warm evaluator excludes
those stages.

## Q08. Import depth and duplicates

The matrix holds the file count (16) and declaration count (1,024) fixed.
Each of the 16 files contributes 64 recipes. The root enables
`allow-duplicate-recipes`. Repeating 0, 16 or 48 names in each file shadows
0, 240 or 720 declarations. Every repeated name has a unique shallowest
definition in the root. The matrix exercises the override policy that was
already supported by both revisions.

Median `--summary` elapsed time in milliseconds, shown as before → after.

| Maximum import depth | 0 shadowed | 240 shadowed | 720 shadowed |
| ---: | ---: | ---: | ---: |
| 1 | 93.25 → 74.15 | 70.58 → 58.63 | 49.03 → 50.17 |
| 4 | 71.62 → 50.92 | 61.56 → 50.86 | 54.82 → 49.03 |
| 15 | 73.24 → 55.55 | 63.42 → 52.70 | 48.14 → 48.11 |

All nine summaries and all six `--show r0` winner checks matched the historical
just 1.57.0 oracle byte for byte on stdout, stderr and exit status. For the
2,000-recipe controls, the single-file median went from 61.68 to 66.37 ms,
and the two-file median went from 187.69 to 75.81 ms. Other work was running
on this host. The timing differences depend on workload and run-to-run noise.

## Q09. File operations

The same probe wrote 1,048,577 deterministic bytes, called the production Wasm
filesystem adapter at the default 64 KiB chunk size, and checked the streamed
content hash against a whole-buffer hash. Both revisions delivered 17 chunks.
Compiler coverage counted calls at the adapter's actual open and read sites.

| Regular-file operations | Before | After |
| --- | ---: | ---: |
| Opens | 18 (1 size query + 17 range reads) | 1 |
| Reads | 17 | 17 |

For the old adapter, the counted lines in `internal/host/wasm/portable.mbt`
are 405 (size open), 52 (range open) and 58 (range read). For #80 they are
lines 21–22 in `internal/host/wasm/stream.mbt`. For Q07 the corresponding
lines in `internal/builtin/registry.mbt` are 281, 242 and 243 before, and
278, 228 and 231 after (lookup, construction, per-spec initialization).
These are adapter operation counts. Throughput and kernel syscall counts were
outside the measurement. The short-read and empty-file tests additionally
check one open across pathname replacement, ordered bytes and digest, and zero
reads for an empty file. [Wasm stream tests](../../internal/host/wasm/stream_wbtest.mbt)

## Reproduction

Run from the repository root with just 1.57.0 on PATH. Use a new temporary
directory for each run so coverage logs belong to a single probe. The command
below reuses the checkout's installed locked dependencies.

```sh
trial=$(mktemp -d)
mkdir "$trial/before" "$trial/after"
git archive 97375e5a4d319da904bb924ba40339d161f926c4 | tar -x -C "$trial/before"
git archive ab99e56d2c2f5b65b893639eabf9a9877785b331 | tar -x -C "$trial/after"
for side in before after; do
  cp -R .mooncakes "$trial/$side/"
  (cd "$trial/$side" && moon build --release --frozen --target wasm .)
done
artifact=_build/wasm/release/build/MoonJust.wasm
moon run tests/benchmark/builtin_imports.mbtx \
  "$trial/before/$artifact" "$trial/after/$artifact" > "$trial/cli.log"
```

The CLI driver discards one warm-up pair, then alternates runner order over
six measured pairs per case. All 26 cases validate every run against the
oracle. For the in-process benchmark, the older revision needs the benchmark
and its test-only `core/bench` import from #80.

```sh
for file in moon.pkg builtin_bench_test.mbt; do
  cp "$trial/after/internal/evaluator/$file" "$trial/before/internal/evaluator/"
done
for side in before after; do
  (cd "$trial/$side" && moon bench --release --target wasm \
    internal/evaluator/builtin_bench_test.mbt) > "$trial/warm-$side.log"
  cp -R tests/benchmark/cost_probe "$trial/$side/tests/benchmark/"
  (cd "$trial/$side" && \
    moon test --target-dir _build/cost --target wasm --enable-coverage tests/benchmark/cost_probe && \
    moon coverage report -f coveralls -o "$trial/cost-$side.json" \
      -t _build/cost/moonbit_coverage_*.txt \
      _build/cost/wasm/debug/test/internal/builtin/builtin.trace.source \
      _build/cost/wasm/debug/test/internal/host/wasm/wasm.trace.source)
done
```

Each coverage JSON has a `source_files` array. Entry `coverage[line - 1]`
contains the count for that source line. Local raw outputs for this run are in
`_build/maintenance/perf-pr80/{cli.log,warm-before.log,warm-after.log,cost-before.json,cost-after.json}`.
